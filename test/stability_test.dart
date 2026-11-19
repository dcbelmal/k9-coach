import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/screens/gps_screen.dart';
import 'package:k9_coach/screens/shell.dart';
import 'package:k9_coach/screens/training.dart';
import 'package:k9_coach/screens/training_start.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:k9_coach/ui_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_prefs.dart';

TrainingSession training(Discipline d, DateTime date) =>
    TrainingSession(id: 't${date.microsecondsSinceEpoch}', discipline: d, date: date, durationMin: 30);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeDisk disk;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    disk = installFakeDisk();
    dir = await useTempFiles();
    OnlineConsent.instance
      ..weather = false
      ..map = false;
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'Belg', weightKg: 30));
    goToTab(0);
    trainingTab.value = 0;
  });

  tearDown(() {
    GpsServices.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('odporność ustawień interfejsu', () {
    test('zły typ wartości: wartości domyślne, a pozostałe psy zachowują ustawienia', () async {
      disk.put(
          'valkor_ui_v1',
          jsonEncode({
            'quick': {
              'main': {'d': 'canicross', 'min': 'trzydzieści', 'km': -4},
              'inny': {'d': 'bikejoring', 'min': 45, 'km': 12},
              'zepsuty': 'nie obiekt',
              'nieznany': {'d': 'latanie'},
            },
            'hidden': 'stats',
          }));
      await restartApp();
      final ui = UiPrefs.instance;
      final main = ui.quickFor('main')!;
      expect(main.discipline, Discipline.canicross);
      expect(main.targetMin, 0);
      expect(main.targetKm, isNull);
      expect(ui.quickFor('inny')!.targetKm, 12);
      expect(ui.quickFor('zepsuty'), isNull);
      expect(ui.quickFor('nieznany'), isNull);
      expect(ui.hidden, isEmpty);
    });

    test('zapis innego typu niż obiekt (np. lista) = ustawienia domyślne, dane psa nietknięte', () async {
      disk.put('valkor_ui_v1', '[1,2,3]');
      await restartApp();
      expect(UiPrefs.instance.hidden, isEmpty);
      expect(currentQuickStart(), isNull);
      expect(AppStore.instance.dog!.name, 'Belg');
      // Po pierwszej zmianie zapis wraca do poprawnej postaci.
      await UiPrefs.instance.setShown(HomeCard.events, false);
      await restartApp();
      expect(UiPrefs.instance.shows(HomeCard.events), isFalse);
    });

    test('równoczesne zmiany i szybkie przełączanie psów: po restarcie wszystko zapisane', () async {
      final p = DogProfiles.instance;
      final a = p.activeId;
      await p.startAdding();
      await AppStore.instance.saveDog(Dog(name: 'Suka'));
      final b = p.activeId;

      await Future.wait([
        UiPrefs.instance.rememberStart(a, const QuickStart(Discipline.igp, targetMin: 20)),
        p.switchTo(a),
        UiPrefs.instance.rememberStart(b, const QuickStart(Discipline.canicross, targetKm: 5)),
        UiPrefs.instance.setShown(HomeCard.stats, false),
        p.switchTo(b),
        UiPrefs.instance.setShown(HomeCard.care, false),
      ]);
      await restartApp();
      expect(UiPrefs.instance.quickFor(a)!.discipline, Discipline.igp);
      expect(UiPrefs.instance.quickFor(a)!.targetKm, isNull, reason: 'IGP nie ma dystansu');
      expect(UiPrefs.instance.quickFor(b)!.targetKm, 5);
      expect(UiPrefs.instance.shows(HomeCard.stats), isFalse);
      expect(UiPrefs.instance.shows(HomeCard.care), isFalse);
    });

    test('błąd zapisu nie cofa późniejszej zmiany tej samej karty', () async {
      disk.holdKeys['valkor_ui_v1'] = Completer<void>();
      disk.full = true;
      final first = UiPrefs.instance.setShown(HomeCard.stats, false);
      final firstDone = expectLater(first, throwsA(anything));
      disk.full = false;
      final second = UiPrefs.instance.setShown(HomeCard.stats, true);
      disk.full = true;
      disk.holdKeys.remove('valkor_ui_v1')!.complete();
      await firstDone;
      disk.full = false;
      await second.catchError((_) {});
      expect(UiPrefs.instance.shows(HomeCard.stats), isTrue);
    });
  });

  group('szybki start i wybór dyscypliny', () {
    test('nowszy trening innej dyscypliny (np. ręczny) wygrywa z zapamiętanym startem', () async {
      final id = DogProfiles.instance.activeId;
      await UiPrefs.instance
          .rememberStart(id, QuickStart(Discipline.canicross, targetMin: 30, at: DateTime(2026, 11, 10)));
      expect(currentQuickStart()!.discipline, Discipline.canicross);
      expect(currentQuickStart()!.targetMin, 30);

      await AppStore.instance.upsertTraining(training(Discipline.obedience, DateTime(2026, 11, 12)));
      expect(currentQuickStart()!.discipline, Discipline.obedience);

      // Starszy wpis ręczny nie zmienia podpowiedzi.
      await UiPrefs.instance
          .rememberStart(id, QuickStart(Discipline.canicross, targetMin: 30, at: DateTime(2026, 11, 13)));
      expect(currentQuickStart()!.discipline, Discipline.canicross);
    });

    test('ostatnio używane dyscypliny na początku, żadna nie znika', () async {
      await AppStore.instance.upsertTraining(training(Discipline.igp, DateTime(2026, 11, 1)));
      await AppStore.instance.upsertTraining(training(Discipline.bikejoring, DateTime(2026, 11, 5)));
      final order = disciplinesByRecent();
      expect(order.take(2), [Discipline.bikejoring, Discipline.igp]);
      expect(order.toSet(), Discipline.values.toSet());
      expect(order.length, Discipline.values.length);
    });

    test('bez historii: stała kolejność', () {
      expect(disciplinesByRecent(), Discipline.values);
    });
  });

  group('ekran treningu', () {
    Widget app(Widget home) => MaterialApp(theme: K9.theme(), home: home);

    testWidgets('podwójne dotknięcie Start nie rozpoczyna dwóch sesji', (tester) async {
      final gate = Completer<LocationPermission>();
      var requests = 0;
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.denied;
      GpsServices.requestPermission = () {
        requests++;
        return gate.future;
      };
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const GpsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(requests, 1, reason: 'drugie dotknięcie w trakcie startu jest ignorowane');
      gate.complete(LocationPermission.denied);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Trening bez GPS (tylko czas)'), findsOneWidget, reason: 'po odmowie są inne drogi');
    });

    testWidgets('szybki start otwiera jeden ekran i nie nagrywa bez dotknięcia Start', (tester) async {
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.whileInUse;
      await tester.pumpWidget(app(Builder(
          builder: (c) => TextButton(
              onPressed: () {
                startQuick(c, const QuickStart(Discipline.canicross, targetMin: 30));
                startQuick(c, const QuickStart(Discipline.canicross, targetMin: 30));
              },
              child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(GpsScreen), findsOneWidget);
      expect(find.text('Start treningu'), findsOneWidget, reason: 'ekran ustawień, nagrywanie nie ruszyło');
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('filtr historii zostaje po zmianie zakładki', (tester) async {
      await tester.runAsync(() async {
        await AppStore.instance.upsertTraining(training(Discipline.igp, DateTime(2026, 11, 1)));
        await AppStore.instance.upsertTraining(training(Discipline.canicross, DateTime(2026, 11, 2)));
      });
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const Shell()));
      await tester.pump(const Duration(seconds: 1));
      openTrainingTab(2);
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(ChoiceChip, 'IGP');
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);

      goToTab(3);
      await tester.pumpAndSettle();
      goToTab(1);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'IGP')).selected, isTrue);
    });
  });
}

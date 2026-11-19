import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/screens/home.dart';
import 'package:k9_coach/screens/shell.dart';
import 'package:k9_coach/screens/training_start.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:k9_coach/ui_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_prefs.dart';

TrainingSession training(Discipline d, DateTime date) =>
    TrainingSession(id: 't${date.microsecondsSinceEpoch}', discipline: d, date: date, durationMin: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeDisk disk;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    disk = installFakeDisk();
    dir = await useTempFiles();
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'Belg', weightKg: 30));
    goToTab(0);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('szybki start treningu', () {
    test('bez zapisanych ustawień: dyscyplina ostatniego treningu psa', () async {
      expect(currentQuickStart(), isNull);
      await AppStore.instance.upsertTraining(training(Discipline.obedience, DateTime(2026, 11, 1)));
      await AppStore.instance.upsertTraining(training(Discipline.canicross, DateTime(2026, 11, 5)));
      expect(currentQuickStart()!.discipline, Discipline.canicross);
    });

    test('ustawienia są osobne dla każdego psa i przetrwają ponowne uruchomienie', () async {
      final p = DogProfiles.instance;
      final first = p.activeId;
      await UiPrefs.instance.rememberStart(first, const QuickStart(Discipline.bikejoring, targetMin: 30, targetKm: 8));

      await p.startAdding();
      await AppStore.instance.saveDog(Dog(name: 'Suka'));
      final second = p.activeId;
      expect(currentQuickStart(), isNull, reason: 'drugi pies nie dziedziczy ustawień pierwszego');

      await restartApp();
      await p.switchTo(first);
      final q = currentQuickStart()!;
      expect(q.discipline, Discipline.bikejoring);
      expect(q.targetMin, 30);
      expect(q.targetKm, 8);

      await p.switchTo(second);
      expect(currentQuickStart(), isNull);
    });

    test('usunięcie psa usuwa jego ustawienia, uszkodzony zapis = ustawienia domyślne', () async {
      final id = DogProfiles.instance.activeId;
      await UiPrefs.instance.rememberStart(id, const QuickStart(Discipline.igp));
      await UiPrefs.instance.forgetDog(id);
      await restartApp();
      expect(UiPrefs.instance.quickFor(id), isNull);

      disk.put('valkor_ui_v1', '{to nie jest json');
      await restartApp();
      expect(UiPrefs.instance.hidden, isEmpty);
      expect(AppStore.instance.dog!.name, 'Belg', reason: 'dane psa są nietknięte');
    });

    test('błąd zapisu wygody nie przerywa startu treningu', () async {
      disk.full = true;
      await UiPrefs.instance.rememberStart('x', const QuickStart(Discipline.walk));
      expect(UiPrefs.instance.quickFor('x')!.discipline, Discipline.walk);
    });
  });

  group('karty ekranu Start', () {
    test('ukryta karta zostaje ukryta po restarcie, błąd zapisu cofa zmianę', () async {
      await UiPrefs.instance.setShown(HomeCard.stats, false);
      await restartApp();
      expect(UiPrefs.instance.shows(HomeCard.stats), isFalse);

      disk.full = true;
      await expectLater(UiPrefs.instance.setShown(HomeCard.stats, true), throwsA(anything));
      expect(UiPrefs.instance.shows(HomeCard.stats), isFalse);
    });

    test('przypomnienia i wydarzenia są rozdzielone', () {
      final t = training(Discipline.igp, DateTime(2026, 12, 1));
      final h = HealthRecord(id: 'h', category: HealthCategory.vaccination, title: 'Wścieklizna', date: DateTime(2026));
      AgendaItem item(Object src) =>
          AgendaItem(date: DateTime(2026, 12, 1), title: '', subtitle: '', icon: Icons.abc, color: K9.orange, source: src);
      expect(isReminder(item(t)), isFalse);
      expect(isReminder(item(h)), isTrue);
    });
  });

  group('ekran Start i nawigacja', () {
    Widget app() => MaterialApp(theme: K9.theme(), home: const Shell());

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('główny przycisk treningu jest od razu widoczny, puste karty się nie pokazują', (tester) async {
      await pump(tester);
      expect(find.text('Rozpocznij trening'), findsOneWidget);
      expect(find.text('Wybierz dyscyplinę i ruszaj'), findsOneWidget);
      expect(find.text('Przypomnienia'), findsNothing);
      expect(find.text('Ostatnia aktywność'), findsNothing);
      expect(find.text('Ten tydzień'), findsNothing);
      // Bez historii przycisk otwiera wybór dyscypliny i sposobu zapisu.
      await tester.tap(find.text('Rozpocznij trening'));
      await tester.pumpAndSettle();
      expect(find.text('Nagrywaj z GPS'), findsOneWidget, reason: 'domyślnie spacer – z GPS');
      expect(find.text('Wpisz ręcznie'), findsOneWidget);
    });

    testWidgets('po treningu: ostatnia aktywność, tydzień i start jednym dotknięciem', (tester) async {
      await tester.runAsync(
          () => AppStore.instance.upsertTraining(training(Discipline.canicross, DateTime.now().subtract(const Duration(hours: 3)))));
      await pump(tester);
      expect(find.text('Ostatnia aktywność'), findsOneWidget);
      expect(find.text('Ten tydzień'), findsOneWidget);
      expect(find.textContaining('Canicross · GPS'), findsOneWidget);
    });

    testWidgets('Wstecz na innej zakładce wraca na Start zamiast zamykać aplikację', (tester) async {
      await pump(tester);
      goToTab(3);
      await tester.pumpAndSettle();
      expect(find.text('Profil psa'), findsOneWidget);
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(tabIndex.value, 0);
      expect(find.text('Rozpocznij trening'), findsOneWidget);
    });

    testWidgets('pozycja przewijania zostaje po zmianie zakładki', (tester) async {
      await pump(tester);
      goToTab(3);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      expect(before, greaterThan(100));

      goToTab(0);
      await tester.pumpAndSettle();
      goToTab(3);
      await tester.pumpAndSettle();
      final after = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      expect(after, before);
    });

    testWidgets('profil psa: sekcje w stałej kolejności, ustawienia osobno', (tester) async {
      await pump(tester);
      goToTab(3);
      await tester.pumpAndSettle();
      expect(find.text('Dane podstawowe'), findsOneWidget);
      expect(find.text('Pomiary i masa ciała'), findsOneWidget);
      expect(find.text('Włącz powiadomienia'), findsNothing, reason: 'ustawienia są na osobnym ekranie');
      await tester.tap(find.byTooltip('Ustawienia aplikacji'));
      await tester.pumpAndSettle();
      expect(find.text('Moduły'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
    });
  });
}

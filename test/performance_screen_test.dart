import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/modules/module_store.dart';
import 'package:k9_coach/nutrition/nutrition_models.dart';
import 'package:k9_coach/nutrition/nutrition_store.dart';
import 'package:k9_coach/performance/perf_repository.dart';
import 'package:k9_coach/performance/performance_screen.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_prefs.dart';

TrackPoint p(double northM, double t) => TrackPoint(50 + northM / 111195, 20, t);

void main() {
  late Directory dir;
  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    installFakeDisk();
    dir = await useTempFiles();
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'Belg', weightKg: 30, heightCm: 62));
    PerfRepository.instance.clear();
    // 600 s: przewodnik 2 m/s, pies 4 m/s (pomiar co 5 s).
    final tr = Track(
      [
        [for (var s = 0; s <= 600; s += 5) p(s * 2.0, s.toDouble())],
      ],
      [],
      const [],
      [
        [for (var s = 0; s <= 600; s += 5) p(s * 4.0, s.toDouble())],
      ],
    ).encode();
    PerfRepository.readTrack = (ref) async => ref == 't1' ? tr : null;
  });
  tearDown(() {
    PerfRepository.readTrack = (_) async => null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: w));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('bez Premium: opis i przejście do Premium, bez danych', (tester) async {
    await pump(tester, const PerformanceScreen());
    expect(find.text('Odblokuj w Premium'), findsOneWidget);
    expect(find.text('Podsumowanie'), findsNothing);
  });

  testWidgets('z Premium: 5 zakładek, dane z trackera, okresy i bilans', (tester) async {
    await tester.runAsync(() async {
      await ModuleStore.instance.setPremium(true, source: PremiumSource.play);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 7);
      await AppStore.instance.upsertTraining(
        TrainingSession(
          id: 'a',
          discipline: Discipline.canicross,
          date: today,
          durationMin: 10,
          distanceKm: 1.2,
          trackRef: 't1',
        ),
      );
      await AppStore.instance.upsertTraining(
        TrainingSession(
          id: 'b',
          discipline: Discipline.igp,
          date: today.add(const Duration(hours: 3)),
          durationMin: 45,
        ),
      );
      await NutritionStore.instance.upsertEntries([
        FeedingEntry(
          id: 'f1',
          date: today.add(const Duration(hours: 1)),
          kind: FeedKind.morning,
          label: 'Karma',
          grams: 300,
          kcal: 1200,
        ),
      ]);
    });
    await pump(tester, const PerformanceScreen());
    expect(tester.takeException(), isNull);
    for (final t in ['Podsumowanie', 'Aktywność', 'Wydajność', 'Kondycja', 'Bilans energetyczny']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('perf-quality')), findsOneWidget);
    expect(find.text('Dobra jakość danych'), findsOneWidget);
    expect(find.text('2,4 km'), findsWidgets, reason: 'dystans psa z trackera');
    expect(find.text('× 2,00'), findsOneWidget, reason: 'pies przebiegł 2× więcej');

    // Filtr dyscyplin: tylko IGP – brak trackera.
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IGP'));
    await tester.pump();
    await tester.tap(find.text('Zastosuj'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Brak danych z trackera'), findsOneWidget);

    for (final tab in ['Aktywność', 'Wydajność', 'Kondycja', 'Bilans energetyczny']) {
      await tester.ensureVisible(find.text(tab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    // Dzień: bilans z wpisem karmienia.
    await tester.tap(find.byKey(const ValueKey('perf-day')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Bilans dnia'), findsOneWidget);
    expect(find.text('1200 kcal'), findsOneWidget);
    expect(find.text('Szacunkowy bilans'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

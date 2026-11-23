import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k9_coach/collar/tracker_driver.dart';
import 'package:k9_coach/gps/dog_stats.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/screens/dog_track_widgets.dart';
import 'package:k9_coach/screens/track_detail.dart';
import 'package:k9_coach/theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// Punkt [northM] m na północ i [eastM] m na wschód od (50, 20) w chwili [t].
TrackPoint p(double northM, double t, [double eastM = 0]) =>
    TrackPoint(50 + northM / 111195, 20 + eastM / (111195 * 0.6427876), t);

/// Przewodnik idzie 1 m/s na północ przez 300 s; pies biega obok.
Track walkWithDog({List<List<TrackPoint>>? dog}) => Track(
      [
        [for (var s = 0; s <= 300; s += 5) p(s.toDouble(), s.toDouble())]
      ],
      [],
      const [],
      dog ??
          [
            [for (var s = 0; s <= 300; s += 10) p(s * 1.0, s.toDouble(), s % 20 == 0 ? 0 : 30)]
          ],
    );

void main() {
  setUpAll(() async => initializeDateFormatting());
  group('Statystyki psa', () {
    test('dystans, stosunek, odległość od przewodnika', () {
      final s = DogStats.of(walkWithDog());
      expect(s.handlerMeters, closeTo(300, 2));
      expect(s.dogMeters, greaterThan(s.handlerMeters));
      expect(s.ratio, greaterThan(1.5));
      expect(s.maxFromHandlerM, closeTo(30, 1));
      expect(s.avgFromHandlerM, closeTo(15, 1.5));
      expect(s.reliable, isTrue);
      expect(s.speedSeries, hasLength(30));
      expect(s.distanceSeries, hasLength(31));
    });

    test('ruch i odpoczynek', () {
      final t = walkWithDog(dog: [
        [p(0, 0), p(50, 10), p(100, 20), p(100.5, 80), p(101, 140)],
      ]);
      final s = DogStats.of(t);
      expect(s.activeSec, 20);
      expect(s.restSec, 120);
      expect(s.maxSpeedMs, closeTo(5, 0.1));
    });

    test('mało i rzadkich pomiarów = statystyki orientacyjne', () {
      final s = DogStats.of(walkWithDog(dog: [
        [p(0, 0), p(30, 30), p(60, 60)],
      ]));
      expect(s.reliable, isFalse);
      expect(s.issues, containsAll([DogStatsIssue.fewPoints, DogStatsIssue.sparse, DogStatsIssue.gaps]));
    });

    test('niemożliwy skok i luka nie zawyżają prędkości', () {
      final s = DogStats.of(walkWithDog(dog: [
        [p(0, 0), p(10, 10), p(2000, 20), p(20, 30)],
        [p(500, 200), p(510, 210)],
      ]));
      expect(s.maxSpeedMs, lessThan(18));
    });

    test('pozycja w chwili t: interpolacja, brak w przerwie', () {
      final segs = [
        [p(0, 0), p(100, 40)],
        [p(500, 300), p(600, 340)],
      ];
      expect(const Distance()(positionAt(segs, 20)!, p(50, 0).ll), lessThan(0.5));
      expect(positionAt(segs, 200), isNull);
      expect(positionAt([
        [p(0, 0), p(100, 200)]
      ], 100), isNull); // 200 s bez pomiaru
    });

    test('przedziały intensywności', () {
      expect(intensityBand(0.5), 0);
      expect(intensityBand(3), 1);
      expect(intensityBand(5), 2);
      expect(intensityBand(9), 3);
    });
  });

  group('Tropienie IGP', () {
    test('odległość od łamanej', () {
      final path = [p(0, 0), p(100, 1)];
      expect(distanceToPath(p(50, 0, 10).ll, path), closeTo(10, 0.3));
      expect(distanceToPath(p(150, 0).ll, path), closeTo(50, 0.5));
    });

    test('pies blisko śladu i z odejściem', () {
      final laid = [for (var i = 0; i <= 10; i++) p(i * 10.0, i.toDouble())];
      final dog = [for (var i = 0; i <= 10; i++) p(i * 10.0, i.toDouble(), i == 5 ? 25 : 3)];
      final a = TrackingAnalysis.compare(laid, dog)!;
      expect(a.maxDevM, closeTo(25, 0.5));
      expect(a.within10, closeTo(10 / 11, 0.01));
      expect(a.covered, greaterThan(0.9));
      expect(TrackingAnalysis.compare([p(0, 0)], dog), isNull);
    });
  });

  group('Sterowniki urządzeń', () {
    test('dostępne mają prawdziwe funkcje, w przygotowaniu – żadnych', () {
      for (final m in TrackerModels.all) {
        if (m.available) {
          expect(m.caps, isNotEmpty);
        } else {
          expect(m.caps, isEmpty);
        }
      }
      expect(TrackerModels.t1000e.caps, isNot(contains(TrackerCapability.historySync)));
      expect(TrackerModels.t1000e.caps, isNot(contains(TrackerCapability.cellular)));
      expect(TrackerDrivers.active.has(TrackerCapability.bluetooth), isTrue);
    });
  });

  group('Ekran treningu z psem', () {
    setUp(() {
      GpsServices.reset();
      GpsServices.tiles = () => const SizedBox.shrink();
      OnlineConsent.instance.map = false;
    });
    tearDown(GpsServices.reset);

    Future<void> open(WidgetTester tester, Discipline d) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = TrainingSession(id: 'x', discipline: d, date: DateTime(2026, 11, 23, 10), durationMin: 5, distanceKm: 0.3)
        ..trackRef = 'tracks/x.json';
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: TrackDetailScreen(training: t, track: walkWithDog())));
      await tester.pump();
    }

    testWidgets('statystyki, wykresy i odtwarzanie', (tester) async {
      await open(tester, Discipline.walk);
      expect(tester.takeException(), isNull);
      expect(find.byType(DogStatsCard), findsOneWidget);
      expect(find.text('Prędkość psa (km/h)'), findsOneWidget);
      expect(find.text('Odległość psa od Ciebie (m)'), findsOneWidget);
      expect(find.byType(DogReplayCard), findsOneWidget);
      expect(find.byType(IgpTrackingCard), findsNothing);
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();
      expect(find.textContaining('od Ciebie'), findsWidgets);
    });

    testWidgets('IGP: karta porównania ze śladem', (tester) async {
      await open(tester, Discipline.igp);
      expect(find.byType(IgpTrackingCard), findsOneWidget);
      expect(find.textContaining('nie zastępuje oceny sędziego'), findsOneWidget);
    });
  });
}

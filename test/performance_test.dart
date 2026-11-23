import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/performance/perf_energy.dart';
import 'package:k9_coach/performance/perf_model.dart';
import 'package:k9_coach/performance/perf_period.dart';
import 'package:k9_coach/performance/perf_repository.dart';

/// Punkt [northM] m na północ od (50, 20) w chwili [t] s.
TrackPoint p(double northM, double t) => TrackPoint(50 + northM / 111195, 20, t);

TrainingSession sess(
  String id,
  DateTime date, {
  Discipline d = Discipline.canicross,
  int min = 30,
  double? km,
  String? track,
  int rpe = 5,
}) => TrainingSession(id: id, discipline: d, date: date, durationMin: min, distanceKm: km, trackRef: track, rpe: rpe);

/// Przewodnik 2 m/s przez [sec] s; pies wg [dog].
Track track(List<List<TrackPoint>> dog, {int sec = 600}) => Track(
  [
    [for (var s = 0; s <= sec; s += 5) p(s * 2.0, s.toDouble())],
  ],
  [],
  const [],
  dog,
);

/// Pies biegnie ze stałą prędkością [v] m/s, pomiar co [step] s.
List<TrackPoint> run(double v, {int from = 0, int to = 600, int step = 5, double start = 0}) => [
  for (var s = from; s <= to; s += step) p(start + (s - from) * v, s.toDouble()),
];

void main() {
  group('Strefy wg chodu', () {
    test('z wysokości w kłębie (Froude)', () {
      final z = GaitZones.forDog(heightCm: 60, kg: 30);
      expect(z.fromHeight, isTrue);
      expect(z.walkTrot, closeTo(math.sqrt(0.5 * 9.81 * 0.6), 1e-9)); // ≈1,72 m/s
      expect(z.trotGallop, closeTo(math.sqrt(2.5 * 9.81 * 0.6), 1e-9)); // ≈3,84 m/s
      expect(z.zoneOf(0.2), PerfZone.rest);
      expect(z.zoneOf(1.2), PerfZone.low);
      expect(z.zoneOf(2.5), PerfZone.moderate);
      expect(z.zoneOf(6), PerfZone.high);
    });

    test('mały pies ma niższe progi niż duży', () {
      final small = GaitZones.forDog(heightCm: 25), big = GaitZones.forDog(heightCm: 70);
      expect(small.trotGallop, lessThan(big.trotGallop));
      // 3 m/s to galop dla małego psa, a kłus dla dużego.
      expect(small.zoneOf(3), PerfZone.high);
      expect(big.zoneOf(3), PerfZone.moderate);
    });

    test('bez wzrostu – z masy (Heglund 1974); bez danych – pies ok. 25 kg', () {
      final z = GaitZones.forDog(kg: 30);
      expect(z.fromHeight, isFalse);
      expect(z.trotGallop, closeTo(1.53 * math.pow(30, 0.24), 1e-9));
      expect(GaitZones.forDog().trotGallop, closeTo(1.53 * math.pow(25, 0.24), 1e-9));
      expect(GaitZones.forDog(heightCm: 500, kg: 30).fromHeight, isFalse, reason: 'błędny wzrost ignorujemy');
    });
  });

  group('Wydatek energetyczny', () {
    test('koszt netto ruchu wg Taylora (1982)', () {
      // 10,7 × 25^−0,316 J/(kg·m) = 3,868 J/(kg·m) = 0,9245 kcal/(kg·km)
      expect(DogEnergyModel.locomotionKcal(25, 10000), closeTo(231.1, 0.5));
      // Mniejszy pies – wyższy koszt na kg.
      expect(DogEnergyModel.locomotionKcal(5, 1000) / 5, greaterThan(DogEnergyModel.locomotionKcal(40, 1000) / 40));
      expect(DogEnergyModel.locomotionKcal(0, 1000), 0);
      expect(DogEnergyModel.locomotionKcal(20, -5), 0);
    });

    test('RER wg NRC: 70 × M^0,75', () {
      expect(DogEnergyModel.rer(10), closeTo(70 * math.pow(10, 0.75), 1e-9));
    });

    test('źródło szacunku i doliczanie tylko wysiłku ponad zwykły dzień', () {
      final none = DogEnergyModel.estimate(discipline: Discipline.canicross, kg: null, handlerMeters: 5000);
      expect(none.source, KcalSource.none);
      final igp = DogEnergyModel.estimate(discipline: Discipline.igp, kg: 30, handlerMeters: 2000);
      expect(igp.source, KcalSource.none, reason: 'IGP bez trackera – brak dystansu psa');
      final cc = DogEnergyModel.estimate(discipline: Discipline.canicross, kg: 30, handlerMeters: 5000);
      expect(cc.source, KcalSource.handlerDistance);
      expect(cc.extra, isTrue);
      final walk = DogEnergyModel.estimate(discipline: Discipline.walk, kg: 30, dogActiveMeters: 3000);
      expect(walk.source, KcalSource.dogGps);
      expect(walk.extra, isFalse, reason: 'spacer jest już w zapotrzebowaniu podstawowym');
      expect(walk.low, closeTo(walk.kcal * 0.75, 1e-9));
    });
  });

  group('Wskaźniki treningu', () {
    test('trening z trackerem: dystans, strefy, czas ruchu i odpoczynku', () {
      // 300 s galopu 4 m/s, potem 300 s postoju.
      final dog = [...run(4, to: 300), for (var s = 305; s <= 600; s += 5) p(1200, s.toDouble())];
      final m = SessionMetrics.of(sess('a', DateTime(2026, 11, 2), km: 1.2), track([dog]), kg: 30, heightCm: 62);
      expect(m.quality, DataQuality.good);
      expect(m.dogMeters, closeTo(1200, 5));
      expect(m.handlerMeters, closeTo(1200, 5));
      expect(m.ratio, closeTo(1, 0.01));
      expect(m.movingSec, closeTo(300, 1));
      expect(m.restSec, closeTo(300, 1));
      expect(m.avgSpeedMs, closeTo(4, 0.05));
      expect(m.maxSpeedMs, closeTo(4, 0.05));
      expect(m.zoneSec[PerfZone.high.index], closeTo(300, 1));
      expect(m.kcal.source, KcalSource.dogGps);
      expect(m.kcal.kcal, closeTo(DogEnergyModel.locomotionKcal(30, 1200), 2));
      expect(m.elevationGainM, isNull);
    });

    test('utrata sygnału: brak dystansu i czasu przez lukę', () {
      // Dwa odcinki po 100 s z 3 m/s, między nimi 200 s bez sygnału (pies „przeskakuje” 900 m).
      final m = SessionMetrics.of(
        sess('a', DateTime(2026, 11, 2)),
        track([run(3, to: 100), run(3, from: 300, to: 400, start: 1200)], sec: 400),
        kg: 25,
      );
      expect(m.dogMeters, closeTo(600, 5));
      expect(m.movingSec, closeTo(200, 1));
      expect(m.noDataSec, closeTo(200, 1));
      expect(m.quality, DataQuality.partial, reason: 'pokrycie 50%');
    });

    test('błędny skok pozycji nie dodaje dystansu ani prędkości', () {
      final dog = run(2, to: 300);
      dog[30] = p(dog[30].lat * 0 + 5000, dog[30].t); // skok o kilka km
      final m = SessionMetrics.of(sess('a', DateTime(2026, 11, 2)), track([dog], sec: 300), kg: 25);
      expect(m.maxSpeedMs, lessThan(18));
      expect(m.dogMeters, lessThan(700));
    });

    test('za mało pomiarów: statystyki psa niedostępne, bez zgadywania', () {
      final m = SessionMetrics.of(
        sess('a', DateTime(2026, 11, 2), km: 3),
        track([
          [p(0, 0), p(100, 30), p(200, 60)],
        ]),
        kg: 25,
      );
      expect(m.quality, DataQuality.insufficient);
      expect(m.dogMeters, isNull);
      expect(m.avgSpeedMs, isNull);
      expect(m.kcal.source, KcalSource.handlerDistance);
    });

    test('rzadkie pomiary (co 90 s) = dane niewystarczające', () {
      final m = SessionMetrics.of(
        sess('a', DateTime(2026, 11, 2)),
        track([run(2, to: 1800, step: 90)], sec: 1800),
        kg: 25,
      );
      expect(m.quality, DataQuality.insufficient);
    });

    test('starszy trening bez trasy: tylko dane wpisane ręcznie', () {
      final m = SessionMetrics.of(sess('a', DateTime(2026, 11, 2), min: 45, d: Discipline.igp), null, kg: 30);
      expect(m.quality, DataQuality.none);
      expect(m.dogMeters, isNull);
      expect(m.movingSec, 45 * 60);
      expect(m.kcal.source, KcalSource.none);
      expect(m.load, 45 * 5);
    });
  });

  group('Masa w dniu treningu', () {
    final w = [
      WeightEntry(id: '1', date: DateTime(2026, 1, 10), kg: 28),
      WeightEntry(id: '2', date: DateTime(2026, 3, 1, 18), kg: 30),
    ];
    test('ostatni pomiar do dnia treningu włącznie', () {
      expect(weightOn(DateTime(2026, 2, 1), w, 31), 28);
      expect(weightOn(DateTime(2026, 3, 1, 7), w, 31), 30);
      expect(weightOn(DateTime(2026, 5, 1), w, 31), 30);
    });
    test('przed pierwszym pomiarem – najbliższy późniejszy; bez historii – profil', () {
      expect(weightOn(DateTime(2025, 12, 1), w, 31), 28);
      expect(weightOn(DateTime(2026, 1, 1), const [], 31), 31);
      expect(weightOn(DateTime(2026, 1, 1), const [], null), isNull);
    });
  });

  group('Podwójne naliczanie', () {
    final d = DateTime(2026, 11, 2, 8);
    test('ten sam id, ta sama trasa, nakładający się wpis ręczny', () {
      final gps = sess('g', d, km: 5, track: 'f1');
      final (kept, skipped) = dedupeSessions([
        gps,
        sess('g', d, km: 5, track: 'f1'),
        sess('g2', d.add(const Duration(minutes: 1)), km: 5, track: 'f1'),
        sess('m', d.add(const Duration(minutes: 5)), km: 5), // ręczny wpis tego samego biegu
        sess('later', d.add(const Duration(hours: 3)), km: 2),
      ]);
      expect(kept.map((t) => t.id), ['g', 'later']);
      expect(skipped, 3);
    });

    test('kolejne treningi tego samego dnia zostają', () {
      final (kept, skipped) = dedupeSessions([
        sess('a', d, min: 30),
        sess('b', d.add(const Duration(minutes: 25)), min: 30), // zachodzi 5 min
      ]);
      expect(kept, hasLength(2));
      expect(skipped, 0);
    });
  });

  group('Okresy i porównania', () {
    test('zakresy dnia, tygodnia (od poniedziałku), miesiąca, roku', () {
      final a = DateTime(2026, 11, 19, 15); // czwartek
      expect(rangeFor(PerfPeriod.day, a), DateRange(DateTime(2026, 11, 19), DateTime(2026, 11, 20)));
      expect(rangeFor(PerfPeriod.week, a), DateRange(DateTime(2026, 11, 16), DateTime(2026, 11, 23)));
      expect(rangeFor(PerfPeriod.month, a), DateRange(DateTime(2026, 11), DateTime(2026, 12)));
      expect(rangeFor(PerfPeriod.year, a), DateRange(DateTime(2026), DateTime(2027)));
      final c = rangeFor(PerfPeriod.custom, a, custom: DateRange(DateTime(2026, 10, 1, 9), DateTime(2026, 10, 11)));
      expect(c.days, 10);
    });

    test('poprzedni okres', () {
      expect(
        previousRange(PerfPeriod.month, DateRange(DateTime(2026, 3), DateTime(2026, 4))),
        DateRange(DateTime(2026, 2), DateTime(2026, 3)),
      );
      expect(
        previousRange(PerfPeriod.year, DateRange(DateTime(2026), DateTime(2027))),
        DateRange(DateTime(2025), DateTime(2026)),
      );
      expect(
        previousRange(PerfPeriod.week, DateRange(DateTime(2026, 11, 16), DateTime(2026, 11, 23))),
        DateRange(DateTime(2026, 11, 9), DateTime(2026, 11, 16)),
      );
      // Zmiana czasu (marzec) nie gubi dnia.
      expect(
        previousRange(PerfPeriod.week, DateRange(DateTime(2026, 3, 30), DateTime(2026, 4, 6))).from,
        DateTime(2026, 3, 23),
      );
    });

    test('zmiana procentowa – bez dzielenia przez zero', () {
      expect(pctChange(150, 100), closeTo(50, 1e-9));
      expect(pctChange(50, 100), closeTo(-50, 1e-9));
      expect(pctChange(10, 0), isNull);
      expect(pctChange(null, 5), isNull);
    });

    test('filtr dyscyplin i zakres', () {
      final all = [
        sess('a', DateTime(2026, 11, 2, 8)),
        sess('b', DateTime(2026, 11, 3, 8), d: Discipline.walk),
        sess('c', DateTime(2026, 12, 1, 8)),
        sess('x', DateTime(2026, 11, 4, 8))..done = false,
      ];
      final r = DateRange(DateTime(2026, 11), DateTime(2026, 12));
      expect(selectSessions(all, r).$1.map((t) => t.id), ['a', 'b']);
      expect(selectSessions(all, r, only: {Discipline.walk}).$1.map((t) => t.id), ['b']);
    });

    test('podsumowanie: sumy, stosunek tylko z pełnych danych, rekordy', () {
      final s1 = SessionMetrics.of(
        sess('a', DateTime(2026, 11, 2), km: 2.4),
        track([run(4, to: 600)]),
        kg: 30,
        heightCm: 60,
      );
      final s2 = SessionMetrics.of(sess('b', DateTime(2026, 11, 3), km: 5), null, kg: 30);
      final s3 = SessionMetrics.of(sess('c', DateTime(2026, 11, 4), d: Discipline.igp), null, kg: 30);
      final sum = PerfSummary([s1, s2, s3]);
      expect(sum.count, 3);
      expect(sum.dogSessions, 1);
      expect(sum.dogMeters, closeTo(2400, 10));
      expect(sum.handlerMeters, closeTo(1200 + 5000, 10)); // trasa telefonu ma pierwszeństwo przed wpisanym dystansem
      expect(sum.ratio, closeTo(2, 0.02), reason: 'trening bez trackera nie zaniża stosunku');
      expect(sum.avgSpeedMs, closeTo(4, 0.05));
      expect(sum.kcal, closeTo(s1.kcal.kcal + s2.kcal.kcal, 1e-6));
      expect(sum.kcalFromHandler, 1);
      expect(sum.longestDog!.session.id, 'a');
      expect(sum.highestLoad!.value, 150);
      expect(sum.quality, DataQuality.good);
      expect(const PerfSummary([]).dogMeters, isNull);
      expect(const PerfSummary([]).intensityShare, isNull);
      expect(const PerfSummary([]).quality, DataQuality.none);
    });

    test('trend: dni w tygodniu, tygodnie w kwartale, miesiące w roku', () {
      final m = [SessionMetrics.of(sess('a', DateTime(2026, 11, 18, 9), km: 3), null, kg: 30)];
      final w = trend(m, rangeFor(PerfPeriod.week, DateTime(2026, 11, 18)));
      expect(w, hasLength(7));
      expect(w[2].$2.count, 1);
      expect(trend(m, rangeFor(PerfPeriod.year, DateTime(2026, 11, 18))), hasLength(12));
      final q = trend(m, DateRange(DateTime(2026, 9, 1), DateTime(2026, 12, 1)));
      expect(q.length, inInclusiveRange(13, 14));
      expect(q.fold<int>(0, (a, e) => a + e.$2.count), 1);
    });
  });

  group('Wczytywanie tras', () {
    tearDown(() => PerfRepository.readTrack = (_) async => null);
    test('uszkodzony plik trasy = trening bez trasy; wynik w pamięci podręcznej', () async {
      var reads = 0;
      PerfRepository.instance.clear();
      PerfRepository.readTrack = (ref) async {
        reads++;
        return ref == 'ok' ? track([run(3, to: 300)], sec: 300).encode() : '{zepsuty';
      };
      final dog = Dog(name: 'Belg', weightKg: 30, heightCm: 62);
      final list = [
        sess('a', DateTime(2026, 11, 2), track: 'ok'),
        sess('b', DateTime(2026, 11, 3), track: 'bad', km: 2),
      ];
      final m = await PerfRepository.instance.metricsFor(list, dogId: 'main', dog: dog, weights: const []);
      expect(m[0].dogMeters, closeTo(900, 5));
      expect(m[1].quality, DataQuality.none);
      expect(m[1].handlerMeters, 2000);
      await PerfRepository.instance.metricsFor(list, dogId: 'main', dog: dog, weights: const []);
      expect(reads, 2);
      // Inny pies – osobne wyniki (inna masa).
      final other = await PerfRepository.instance.metricsFor(
        list,
        dogId: 'reks',
        dog: Dog(name: 'Reks', weightKg: 10),
        weights: const [],
      );
      expect(other[0].kg, 10);
    });
  });

  group('Bilans energetyczny', () {
    test('bilans = spożyte − (podstawowe + dodatkowe); spacer nie liczony drugi raz', () {
      final walk = SessionMetrics.of(sess('w', DateTime(2026, 11, 2, 8), d: Discipline.walk, km: 4), null, kg: 30);
      final cc = SessionMetrics.of(sess('c', DateTime(2026, 11, 2, 17), km: 5), null, kg: 30);
      final (extra, routine) = activityKcal([walk, cc]);
      expect(extra, closeTo(cc.kcal.kcal, 1e-9));
      expect(routine, closeTo(walk.kcal.kcal, 1e-9));
      final d = DayEnergy(DateTime(2026, 11, 2), eatenKcal: 1500, rerKcal: 900, baseKcal: 1400, extraKcal: extra);
      expect(d.balance, closeTo(1500 - 1400 - extra, 1e-9));
      expect(DayEnergy(DateTime(2026, 11, 2), baseKcal: 1400).balance, isNull, reason: 'bez wpisów karmienia');
      expect(DayEnergy(DateTime(2026, 11, 2), eatenKcal: 1000).balance, isNull, reason: 'bez masy');
    });

    test('średnie tylko z dni z wpisami karmienia; bez dni przyszłych', () {
      final p = EnergyPeriod([
        DayEnergy(DateTime(2026, 11, 1), eatenKcal: 1200, baseKcal: 1000),
        DayEnergy(DateTime(2026, 11, 2), baseKcal: 1000),
        DayEnergy(DateTime(2026, 11, 3), eatenKcal: 800, baseKcal: 1000, extraKcal: 100),
      ]);
      expect(p.withFood, hasLength(2));
      expect(p.avgBalance, closeTo((200 + -300) / 2, 1e-9));
      expect(p.totalExtra, 100);
      final days = daysIn(DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), today: DateTime(2026, 11, 10, 15));
      expect(days, hasLength(10));
      expect(const EnergyPeriod([]).avgBalance, isNull);
    });
  });
}

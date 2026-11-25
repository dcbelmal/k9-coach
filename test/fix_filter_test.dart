import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/fix_filter.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/gps_drafts.dart';
import 'package:k9_coach/gps/recorder.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/models.dart';

final t0 = DateTime.utc(2026, 11, 23, 12);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));

/// ~111 m na 0,001° szerokości.
MeshPosition pos(double dLatM, {num? time, int? sats, double? hdop, int? fixType, double? speed, int? bits}) =>
    MeshPosition(50 + dLatM / 111195, 20,
        time: time == null ? null : at(time), sats: sats, hdop: hdop, fixType: fixType, speedMs: speed, precisionBits: bits);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Filtr pomiarów GPS', () {
    late FixFilter f;
    setUp(() => f = FixFilter(7));

    test('czas pomiaru z pakietu, nie chwila odbioru', () {
      final v = f.check(pos(0, time: 0), at(20));
      expect(v.accepted, isTrue);
      expect(v.fix!.fixAt, at(0));
      expect(v.fix!.lagSec, 20);
    });

    test('zły zegar trackera („z przyszłości” > 10 min) – używamy chwili odbioru', () {
      final v = f.check(pos(0, time: 5000), at(0));
      expect(v.fix!.fixAt, at(0));
      expect(v.fix!.timeIsFix, isFalse);
    });

    test('pomiar sprzed ponad 15 min to stary pakiet, nie zły zegar', () {
      expect(f.check(pos(0, time: -5000), at(0)).reject, FixReject.previousSession);
    });

    test('pomiar „z przyszłości” przycięty do chwili odbioru', () {
      expect(f.check(pos(0, time: 5), at(0)).fix!.fixAt, at(0));
    });

    test('nieaktualny pomiar (> 2 min) odrzucony', () {
      expect(f.check(pos(0, time: 0), at(121)).reject, FixReject.stale);
    });

    test('duplikat i zła kolejność', () {
      expect(f.check(pos(0, time: 10), at(11)).accepted, isTrue);
      // Ten sam czas pomiaru GPS w nowym pakiecie = ten sam pomiar (nie odświeża aktualności).
      expect(f.check(pos(0, time: 10), at(12)).reject, FixReject.repeated);
      expect(f.check(pos(20, time: 5), at(13)).reject, FixReject.outOfOrder);
    });

    test('słaby sygnał: mało satelitów, fix 2D, duży błąd', () {
      expect(f.check(pos(0, time: 0, sats: 3), at(1)).reject, FixReject.weak);
      expect(f.check(pos(0, time: 1, fixType: 2), at(2)).reject, FixReject.weak);
      expect(f.check(pos(0, time: 2, hdop: 20), at(3)).reject, FixReject.weak); // 20 × 5 m = 100 m
      expect(f.check(pos(0, time: 3, sats: 8, hdop: 1.2), at(4)).accepted, isTrue);
    });

    test('zaokrąglona pozycja odrzucona', () {
      expect(f.check(pos(0, time: 0, bits: 13), at(1)).reject, FixReject.coarse);
    });

    test('niemożliwy skok odrzucony, kolejny poprawny pomiar przyjęty', () {
      expect(f.check(pos(0, time: 0), at(1)).accepted, isTrue);
      expect(f.check(pos(1000, time: 10), at(11)).reject, FixReject.jump); // 100 m/s
      expect(f.check(pos(60, time: 20), at(21)).accepted, isTrue); // 3 m/s
    });

    test('dryf w miejscu nie jest ruchem', () {
      f.check(pos(0, time: 0), at(1));
      final v = f.check(pos(2, time: 10), at(11));
      expect(v.accepted, isTrue);
      expect(v.fix!.moved, isFalse);
      // Mały ruch, ale tracker podaje prędkość – to ruch.
      expect(f.check(pos(2.5, time: 20, speed: 2), at(21)).fix!.moved, isTrue);
      // Kilkanaście metrów – ruch.
      expect(f.check(pos(20, time: 30), at(31)).fix!.moved, isTrue);
    });

    test('pakiety bez czasu (stare urządzenia) nadal działają', () {
      expect(f.check(pos(0), at(0)).accepted, isTrue);
      expect(f.check(pos(30), at(10)).accepted, isTrue);
    });
  });

  group('Stan łączności i diagnostyka', () {
    final c = CollarLink.instance;
    setUp(c.resetForTest);

    test('rozróżnia brak trackera, Bluetooth, GPS, na żywo i ostatnią znaną pozycję', () {
      expect(c.status(), DogLink.none);
      c.deviceId = 'x';
      expect(c.status(), DogLink.bluetoothOff);
      c.state = CollarState.connecting;
      expect(c.status(), DogLink.connecting);
      c.state = CollarState.connected;
      c.handleEvents([const MeshMyInfo(3)]);
      expect(c.status(), DogLink.waitingGps);
      final now = DateTime.now();
      c.handleEvents([MeshPositionEvent(3, MeshPosition(50, 20, time: now))]);
      expect(c.status(now: now), DogLink.live);
      expect(c.status(now: now.add(const Duration(minutes: 5))), DogLink.stale);
      expect(c.diag.positions, 1);
      expect(c.diag.accepted, 1);
    });

    test('odrzucone pomiary są liczone według powodu', () {
      c.handleEvents([
        const MeshMyInfo(3),
        const MeshPositionEvent(3, MeshPosition(50, 20, sats: 2)),
        const MeshPositionEvent(3, MeshPosition(50, 20, precisionBits: 13)),
      ]);
      expect(c.diag.rejected[FixReject.weak], 1);
      expect(c.diag.rejected[FixReject.coarse], 1);
      expect(c.dogWithFix, isNull);
    });

    test('mediana odstępów pomiarów', () {
      final d = CollarDiagnostics();
      expect(d.medianInterval, isNull);
      for (final s in [5.0, 6.0, 30.0, 5.0, 4.0]) {
        d.addInterval(s);
      }
      expect(d.medianInterval, 5);
    });
  });

  group('Zapis trasy psa', () {
    late TrackRecorder r;
    setUp(() {
      r = TrackRecorder.instance;
      r.state = RecState.running;
      r.dogSegments = [];
      r.dogMeters = 0;
      r.dogNode = 7;
      r.dogLast = null;
    });
    tearDown(() => r.state = RecState.idle);

    CollarFix fx(double dLatM, num s, {int node = 7, bool moved = true}) =>
        CollarFix(node, 50 + dLatM / 111195, 20, at(s), moved: moved);

    test('inny tracker nie trafia do trasy (źródło zablokowane na treningu)', () {
      r.onDogFix(fx(0, 0, node: 9));
      expect(r.dogPoints, isEmpty);
      r.onDogFix(fx(0, 0));
      expect(r.dogPoints, hasLength(1));
    });

    test('luka w sygnale = nowy segment, bez dystansu przez lukę', () {
      r.onDogFix(fx(0, 0));
      r.onDogFix(fx(30, 10));
      r.onDogFix(fx(500, 200)); // 190 s przerwy
      r.onDogFix(fx(530, 210));
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(2));
      expect(r.dogMeters, closeTo(60, 1));
    });

    test('postój (bez ruchu) nie dodaje punktów ani dystansu', () {
      r.onDogFix(fx(0, 0));
      r.onDogFix(fx(1, 10, moved: false));
      expect(r.dogPoints, hasLength(1));
      expect(r.dogMeters, 0);
      expect(r.dogLast!.fixAt, at(10));
    });

    test('pauza: pozycja odświeżona, punkt nie dodany; po wznowieniu nowy segment', () {
      r.onDogFix(fx(0, 0));
      r.state = RecState.paused;
      r.onDogFix(fx(100, 20));
      expect(r.dogPoints, hasLength(1));
      expect(r.dogLast!.fixAt, at(20));
    });
  });

  group('Zgodność zapisanych danych', () {
    test('segmenty psa zapisane i odczytane; stary format „dog” = jeden segment', () {
      final t = Track([
        [const TrackPoint(50, 20, 0), const TrackPoint(50.001, 20, 10)]
      ], [], const [], [
        [const TrackPoint(50, 20, 0), const TrackPoint(50.0005, 20, 10)],
        [const TrackPoint(50.01, 20, 200), const TrackPoint(50.0105, 20, 210)],
      ]);
      final back = Track.decode(t.encode());
      expect(back.dogSegments, hasLength(2));
      expect(back.dogMeters, closeTo(t.dogMeters, 0.01));
      expect(back.dogSeconds, 20);
      final legacy = decodeDogSegments(null, [
        [50, 20, 0],
        [50.001, 20, 10],
      ]);
      expect(legacy, hasLength(1));
    });

    test('szkic treningu: nowy klucz i stary „dogTrack”', () {
      final d = GpsDraft(
        sessionId: 's',
        dogId: 'd',
        discipline: Discipline.values.first,
        startedAt: t0,
        dogSegments: [
          [const TrackPoint(50, 20, 0)],
          [const TrackPoint(50.01, 20, 100)],
        ],
      );
      final j = d.toJson();
      expect(GpsDraft.fromJson(j).dogSegments, hasLength(2));
      expect(GpsDraft.fromJson(j).dogId, 'd');
      // Stary szkic: płaska lista „dogTrack”.
      final old = Map<String, dynamic>.from(j)
        ..remove('dogTrackSeg')
        ..['dogTrack'] = [
          [50, 20, 0],
          [50.001, 20, 10],
        ];
      expect(GpsDraft.fromJson(old).dogSegments, hasLength(1));
    });
  });
}

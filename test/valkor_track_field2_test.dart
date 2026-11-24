import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy regresyjne z drugiego testu terenowego T1000-E (0.23.1):
/// seq stale 1, 20 „duplikatów” na postoju, komunikat o braku świeżej
/// pozycji przy psie stojącym obok, 13 m na lince 3 m, błąd Bluetooth 133.

final t0 = DateTime(2026, 11, 24, 20);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const _m = 111195.0;
double north(double m) => 50 + m / _m;
double east(double m) => 20 + m / (_m * math.cos(50 * math.pi / 180));
const _d = Distance();

/// Powtarzalny „szum GPS” (bez losowości – testy zawsze tak samo).
double noise(int i, double amp) => amp * math.sin(i * 2.399) * math.cos(i * 0.731);

MeshPositionEvent ev(double lat, double lng, DateTime fix, int packet, {double hdop = 0.6, double? speedMs}) =>
    MeshPositionEvent(1, MeshPosition(lat, lng, time: fix, seq: 1, hdop: hdop, speedMs: speedMs), packetId: packet);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  setUp(() {
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
  });
  tearDown(() => c.resetForTest());

  test('postój 3 min, pomiary co 5 s z identycznymi współrzędnymi i seq = 1 – cały czas „na żywo”', () {
    for (var s = 0; s <= 180; s += 5) {
      HandlerTrack.instance.add(HandlerFix(at(s), north(2), 20, accuracyM: 6));
      c.handleEvents([ev(50, 20, at(s), 1000 + s)], now: at(s + 1));
      expect(c.status(now: at(s + 2)), DogLink.live, reason: 'po $s s');
    }
    expect(c.diag.rejected, isEmpty);
    expect(c.diag.accepted, 37);
    expect(c.diag.still, 36);
    final dd = c.distanceTo(CollarLink.activeDog(), now: at(182))!;
    expect(dd.withinError, isTrue); // „Pies w pobliżu”
  });

  test('ten sam pakiet odczytany drugi raz i ten sam pomiar w nowym pakiecie – nie odświeżają aktualności', () {
    c.handleEvents([ev(50, 20, at(0), 1)], now: at(1));
    c.handleEvents([ev(50, 20, at(0), 1)], now: at(40));
    c.handleEvents([ev(50, 20, at(0), 2)], now: at(41));
    expect(c.dog!.fix!.fixAt, at(0));
    expect(c.diag.rejected[FixReject.duplicate], 1);
    expect(c.diag.rejected[FixReject.repeated], 1);
  });

  test('spacer psa przy nodze (linka 3 m), szum GPS telefonu ±6 m – „pies w pobliżu”, bez alarmu smyczy 10 m', () {
    final e = AlertEngine(AlertSettings(enabled: true, leashM: 10, lowBattery: null));
    final alerts = <AlertKind>[];
    var nearby = 0, n = 0;
    for (var s = 0; s <= 300; s++) {
      // Telefon co sekundę, z szumem ±6 m, dokładność 8 m.
      HandlerTrack.instance.add(HandlerFix(at(s), north(1.3 * s + noise(s, 6)), east(noise(s + 50, 6)), accuracyM: 8, speedMs: 1.3));
      if (s % 5 == 0) {
        // Pies 2 m z boku, szum trackera ±3 m, pakiet dociera po 1,5 s.
        c.handleEvents([ev(north(1.3 * s + noise(s + 7, 3)), east(2 + noise(s + 99, 3)), at(s), s, speedMs: 1.3)],
            now: at(s + 1.5));
        final now = at(s + 2);
        final dd = c.distanceTo(CollarLink.activeDog(), now: now)!;
        n++;
        if (dd.withinError) nearby++;
        expect(dd.matchedM, lessThan(13), reason: 'po $s s: ${dd.matchedM}');
        alerts.addAll(e
            .evaluate(AlertInput(now: now, link: c.status(now: now), fix: c.dog!.fix, distance: dd))
            .map((a) => a.kind));
      }
    }
    expect(nearby / n, greaterThan(0.9));
    expect(alerts, isEmpty);
  });

  test('pogorszenie dokładności telefonu – rośnie niepewność, nadal „w pobliżu”, a nie fałszywe metry', () {
    for (var s = 0; s <= 30; s++) {
      HandlerTrack.instance.add(HandlerFix(at(s), north(noise(s, s < 15 ? 3 : 15)), 20, accuracyM: s < 15 ? 4 : 25));
    }
    c.handleEvents([ev(north(1), 20, at(10), 1)], now: at(11));
    final good = c.distanceTo(CollarLink.activeDog(), now: at(11))!;
    c.handleEvents([ev(north(1), 20, at(28), 2)], now: at(29));
    final bad = c.distanceTo(CollarLink.activeDog(), now: at(29))!;
    expect(bad.matchedUncertaintyM!, greaterThan(good.matchedUncertaintyM!));
    expect(bad.withinError, isTrue);
  });

  test('odległość nie jest przycinana do smyczy ani zerowana – pies naprawdę 40 m dalej', () {
    for (var s = 0; s <= 20; s++) {
      HandlerTrack.instance.add(HandlerFix(at(s), 50, 20, accuracyM: 5));
    }
    for (var s = 0; s <= 20; s += 5) {
      c.handleEvents([ev(north(40), 20, at(s), s)], now: at(s + 1));
    }
    final dd = c.distanceTo(CollarLink.activeDog(), now: at(21))!;
    expect(dd.matchedM, closeTo(40, 2));
    expect(dd.withinError, isFalse);
  });

  test('brak pozycji przez 70 s przy działającym Bluetooth – „brak nowej pozycji”, nie utrata Bluetooth', () {
    c.handleEvents([ev(50, 20, at(0), 1)], now: at(1));
    expect(c.status(now: at(30)), DogLink.live);
    expect(c.status(now: at(70)), DogLink.stale);
    final e = AlertEngine(AlertSettings(enabled: true, leashM: null, lostSec: 60, lowBattery: null));
    e.evaluate(AlertInput(now: at(30), link: DogLink.live, fix: c.dog!.fix));
    final out = e.evaluate(AlertInput(now: at(95), link: c.status(now: at(95)), fix: c.dog!.fix));
    expect(out.single.kind, AlertKind.lost);
    expect(out.single.text, contains('Bluetooth działa'));
    // Nowy pomiar po przerwie – znowu na żywo.
    c.handleEvents([ev(50, 20, at(71), 2)], now: at(72));
    expect(c.status(now: at(73)), DogLink.live);
    expect(c.diag.intervals.last, 71);
  });

  test('utrata i odzyskanie Bluetooth – osobny stan od braku GPS', () {
    c.handleEvents([ev(50, 20, at(0), 1)], now: at(1));
    c.state = CollarState.lost;
    expect(c.status(now: at(5)), DogLink.connecting);
    c.state = CollarState.connected;
    c.handleEvents([ev(50, 20, at(20), 2)], now: at(21));
    expect(c.status(now: at(22)), DogLink.live);
  });

  group('Bluetooth: kolejka i błąd 133', () {
    test('operacje idą po kolei, nie równolegle', () async {
      final order = <String>[];
      var running = 0, maxRunning = 0;
      Future<void> op(String n) async {
        running++;
        maxRunning = math.max(maxRunning, running);
        order.add('start $n');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add('end $n');
        running--;
      }

      await Future.wait([c.bleOp(() => op('a')), c.bleOp(() => op('b')), c.bleOp(() => op('c'))]);
      expect(maxRunning, 1);
      expect(order, ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
    });

    test('błąd GATT 133 – ograniczone ponawianie, potem czytelny błąd', () async {
      var calls = 0;
      await c.bleOp(() async {
        if (++calls < 2) throw Exception('PlatformException(133, GATT_ERROR)');
      }, retries: 2);
      expect(calls, 2);
      expect(c.diag.bleRetries, 1);

      calls = 0;
      await expectLater(
          c.bleOp(() async {
            calls++;
            throw Exception('PlatformException(133, GATT_ERROR)');
          }, retries: 2),
          throwsException);
      expect(calls, 3);
      expect(c.diag.bleFailures, 1);
      expect(CollarLink.gattHint(Exception('GATT 133')), contains('133'));
    });

    test('błąd 133 przy zapisie konfiguracji – zmiana NIE jest potwierdzona', () async {
      c.writeOverride = (_) async => throw Exception('PlatformException(133, GATT_ERROR)');
      final pos = (PbWriter()
            ..varint(1, 30)
            ..varint(5, 8))
          .toBytes();
      final lora = (PbWriter()
            ..varint(1, 1)
            ..varint(7, 3))
          .toBytes();
      c.handleEvents([MeshConfigEvent(2, pos), MeshConfigEvent(6, lora), const MeshConfigComplete(1)]);
      final err = await c.applyProfile(TrackerProfile.sport);
      expect(err, contains('133'));
      expect(c.applyState, ProfileApply.failed);
      expect(c.trackerMatchesMode, isNot(true));
    });
  });

  group('Filtr adaptacyjny', () {
    test('postój: dryf ±4 m tłumiony do ok. 1–2 m', () {
      final f = PosFilter();
      final out = <LatLng>[];
      for (var i = 0; i < 36; i++) {
        out.add(f.update(LatLng(north(noise(i, 4)), east(noise(i + 13, 4))), at(i * 5), accuracyM: 3, speedMs: 0));
      }
      final last = out.skip(10).toList();
      final spread = last.map((p) => _d(p, const LatLng(50, 20))).reduce(math.max);
      expect(spread, lessThan(2.5));
    });

    test('szybki bieg i gwałtowny zwrot – filtr dogania psa w 1–2 pomiarach', () {
      final f = PosFilter();
      // 8 m/s na północ przez 20 s (pomiar co 2 s), potem nagle na wschód.
      for (var s = 0; s <= 20; s += 2) {
        f.update(LatLng(north(8.0 * s), 20), at(s), accuracyM: 3, speedMs: 8);
      }
      LatLng? p;
      for (var s = 22; s <= 26; s += 2) {
        p = f.update(LatLng(north(160), east(8.0 * (s - 20))), at(s), accuracyM: 3, speedMs: 8);
      }
      final truth = LatLng(north(160), east(48));
      expect(_d(p!, truth), lessThan(8));
    });

    test('trasa i dystans z surowych pomiarów – filtr ich nie zmienia', () {
      c.handleEvents([ev(50, 20, at(0), 1)], now: at(1));
      c.handleEvents([ev(north(30), 20, at(5), 2, speedMs: 6)], now: at(6));
      expect(c.dog!.fix!.ll, LatLng(north(30), 20));
      expect(c.dog!.displayLl, isNot(c.dog!.fix!.ll));
    });
  });

  test('praca przy wygaszonym ekranie: alarmy liczone bez ekranu (licznik w tle, nie widżety)', () async {
    final got = <DogAlert>[];
    final a = DogAlerts.instance..onAlert = got.add;
    await a.save(AlertSettings(enabled: true, leashM: 10, lowBattery: null));
    final now = DateTime.now();
    for (var s = -30; s <= 0; s++) {
      HandlerTrack.instance.add(HandlerFix(now.add(Duration(seconds: s)), 50, 20, accuracyM: 4));
    }
    c.handleEvents([ev(north(60), 20, now.subtract(const Duration(seconds: 10)), 1)], now: now.subtract(const Duration(seconds: 9)));
    a.check(now: now.subtract(const Duration(seconds: 8)));
    c.handleEvents([ev(north(61), 20, now.subtract(const Duration(seconds: 5)), 2)], now: now.subtract(const Duration(seconds: 4)));
    a.check(now: now);
    expect(got.map((e) => e.kind), [AlertKind.leash]);
    a.onAlert = null;
    await a.save(AlertSettings());
    a.resetForTest();
  });

  test('CSV: surowa i przefiltrowana odległość, niepewność, wiek pozycji, różnica czasu', () {
    for (var s = 0; s <= 10; s++) {
      HandlerTrack.instance.add(HandlerFix(at(s), 50, 20, accuracyM: 5));
    }
    c.handleEvents([ev(north(5), 20, at(8), 77)], now: at(9.5));
    final row = c.diag.log.single;
    expect(row.packetId, 77);
    expect(row.distanceM, closeTo(5, 0.5));
    expect(row.filteredDistanceM, isNotNull);
    expect(row.uncertaintyM, isNotNull);
    expect(row.compareDtSec, 0);
    expect(row.lagSec, 1.5);
    final csv = c.diag.csv().split('\n');
    expect(csv.first, contains('odleglosc_filtr_m'));
    expect(csv[1].split(';'), hasLength(FixLogEntry.csvHeader.split(';').length));
  });
}

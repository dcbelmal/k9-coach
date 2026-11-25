import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/distance_view.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:k9_coach/gps/recorder.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy regresyjne z trzeciego testu terenowego T1000-E (0.24.0):
/// GPS telefonu stał do 109,6 s i odległość rosła do 59 m, stara
/// prędkość na postoju, zaległe pakiety po ponownym połączeniu.

final t0 = DateTime(2026, 11, 24, 22);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const _m = 111195.0;
double north(double m) => 50 + m / _m;
const _d = Distance();

/// Powtarzalny „szum GPS”.
double noise(int i, double amp) => amp * math.sin(i * 2.399) * math.cos(i * 0.731);

Position pos(double lat, double lng, DateTime t, {double acc = 4, double speed = 0}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: t,
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

MeshPositionEvent ev(double lat, DateTime fix, int packet, {double? speedMs, double hdop = 0.6}) =>
    MeshPositionEvent(1, MeshPosition(lat, 20, time: fix, seq: 1, hdop: hdop, speedMs: speedMs), packetId: packet);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final loc = PhoneLocation.instance;

  /// Pomiar telefonu przez wspólne źródło lokalizacji (jak z GPS).
  void phone(double lat, num s, {double acc = 4, double speed = 0}) =>
      loc.onPosition(pos(lat, 20, at(s), acc: acc, speed: speed), now: at(s));

  setUp(() async {
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
    await loc.resetForTest();
    DogAlerts.instance.resetForTest();
  });
  tearDown(() async {
    c.resetForTest();
    await loc.resetForTest();
    GpsServices.reset();
  });

  group('Odległość pies–telefon', () {
    test('telefon i tracker obok siebie: „Pies w pobliżu”, 1–2 m', () {
      for (var s = 0; s <= 60; s++) {
        phone(north(noise(s, 1.5)), s, acc: 4);
        if (s % 5 == 0 && s >= 5) c.handleEvents([ev(north(1 + noise(s + 7, 1)), at(s - 2), s)], now: at(s));
      }
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(60));
      expect(v.state, DistanceState.nearby);
      expect(v.m!, lessThan(3));
    });

    test('postój 3 minuty: odległość nie rośnie, telefon nie dolicza dystansu', () {
      final r = TrackRecorder.instance
        ..state = RecState.running
        ..segments = [[]]
        ..meters = 0;
      for (var s = 0; s <= 180; s++) {
        phone(north(noise(s, 3)), s, acc: 6, speed: 0.1);
        r.onPosition(pos(north(noise(s, 3)), 20, at(s), acc: 6, speed: 0.1));
        if (s % 5 == 0 && s >= 5) c.handleEvents([ev(north(2 + noise(s + 3, 2)), at(s - 2), s, speedMs: 0)], now: at(s));
        if (s % 30 == 0 && s > 0) {
          final v = DistanceView.of(c, CollarLink.activeDog(), now: at(s));
          expect(v.state, DistanceState.nearby, reason: 'po $s s');
        }
      }
      expect(r.meters, lessThan(1)); // dryf GPS bez fałszywych metrów
      expect(r.currentSpeedKmh, 0); // postój = 0, nie stara prędkość
      r.state = RecState.idle;
    });

    test('spacer na lince 3 m: kilka metrów, bez fałszywych 10+ m', () {
      for (var s = 0; s <= 120; s++) {
        phone(north(1.3 * s + noise(s, 2)), s, acc: 5, speed: 1.3);
        if (s % 5 == 0 && s >= 5) {
          // Pies 2 m przed przewodnikiem, pomiar dociera po 2 s.
          c.handleEvents([ev(north(1.3 * (s - 2) + 2 + noise(s + 9, 2)), at(s - 2), s, speedMs: 1.3)], now: at(s));
        }
      }
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(120));
      expect(v.hasDistance, isTrue);
      expect(v.m!, lessThan(6));
      expect(v.state, DistanceState.nearby);
    });

    test('GPS telefonu staje na 110 s: „Oczekiwanie na lokalizację telefonu”, bez 59 m i bez alarmu', () async {
      await DogAlerts.instance.save(AlertSettings(enabled: true, leashM: 20, lowBattery: null));
      final got = <DogAlert>[];
      DogAlerts.instance.onAlert = got.add;
      // Idziemy razem 1,3 m/s; telefon przestaje podawać pozycję po 30 s.
      for (var s = 0; s <= 140; s++) {
        if (s <= 30) phone(north(1.3 * s), s, acc: 4, speed: 1.3);
        if (s % 5 == 0 && s >= 5) {
          c.handleEvents([ev(north(1.3 * (s - 1)), at(s - 1), s, speedMs: 1.3)], now: at(s));
          DogAlerts.instance.check(now: at(s));
        }
      }
      // Stara metoda: pies 1,3 m/s × 110 s ≈ 140 m od „zamrożonej” pozycji telefonu.
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(140));
      expect(v.state, DistanceState.waitingPhone);
      expect(v.text, 'Oczekiwanie na lokalizację telefonu');
      expect(v.hasDistance, isFalse);
      expect(v.reason, contains('nieaktualna'));
      final dd = c.distanceTo(CollarLink.activeDog(), now: at(140));
      expect(dd, isNull); // ani dopasowanej, ani bieżącej odległości ze starych danych
      expect(got.where((a) => a.kind == AlertKind.leash), isEmpty);
      // W dzienniku: przyczyna braku odległości.
      expect(c.diag.log.last.noDistanceReason, contains('telefonu'));
      DogAlerts.instance.onAlert = null;
      await DogAlerts.instance.save(AlertSettings());
    });

    test('odzyskanie pozycji telefonu: odległość wraca, przerwa w diagnostyce', () {
      for (var s = 0; s <= 20; s++) {
        phone(north(0.5 * noise(s, 1)), s);
      }
      // 110 s ciszy, potem pomiary wracają.
      for (var s = 130; s <= 140; s++) {
        phone(north(0.5 * noise(s, 1)), s);
      }
      c.handleEvents([ev(north(1), at(133), 1)], now: at(134));
      c.handleEvents([ev(north(1), at(138), 2)], now: at(140));
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(140));
      expect(v.hasDistance, isTrue);
      expect(v.state, DistanceState.nearby);
      expect(loc.maxGapSec, closeTo(110, 0.01));
      expect(loc.state, PhoneGps.ok);
    });

    test('różnica czasu nie jest „0 s”, gdy pozycja telefonu jest trzymana', () {
      phone(north(0), 0, speed: 0);
      c.handleEvents([ev(north(1), at(8), 1)], now: at(9));
      final dd = c.distanceTo(CollarLink.activeDog(), now: at(9))!;
      expect(dd.compareDtSec, closeTo(8, 0.01));
    });

    test('szybki ruch i zmiana kierunku psa: filtr dogania w 1–2 pomiarach', () {
      // Pies biegnie 6 m/s na północ, potem skręca na wschód.
      var lat = 50.0, lng = 20.0;
      final k = math.cos(50 * math.pi / 180);
      for (var i = 1; i <= 12; i++) {
        final s = i * 2;
        if (i <= 6) {
          lat += 12 / _m;
        } else {
          lng += 12 / (_m * k);
        }
        phone(50, s);
        c.handleEvents([MeshPositionEvent(1, MeshPosition(lat, lng, time: at(s), seq: 1, hdop: 0.6, speedMs: 6), packetId: i)],
            now: at(s + 1));
      }
      final n = c.dog!;
      expect(_d(n.displayLl!, LatLng(lat, lng)), lessThan(8));
    });
  });

  group('Wspólne źródło lokalizacji telefonu', () {
    late List<LocationSettings> subs;
    late StreamController<Position> ctrl;
    setUp(() {
      subs = [];
      ctrl = StreamController<Position>.broadcast();
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.whileInUse;
      PhoneLocation.streamFactory = (s) {
        subs.add(s);
        return ctrl.stream;
      };
      PhoneLocation.clock = () => at(0);
    });
    tearDown(() => ctrl.close());

    test('trening i Valkor Track: jedna subskrypcja, co 1 s, bez filtra odległości, z usługą w tle', () async {
      await loc.acquire('valkor_track', title: 'Valkor Track', text: 'x');
      expect(subs, hasLength(1));
      final s = subs.single as AndroidSettings;
      expect(s.distanceFilter, 0);
      expect(s.intervalDuration, const Duration(seconds: 1));
      expect(s.foregroundNotificationConfig, isNotNull); // działa przy wygaszonym ekranie
      // Trening dołącza: ta sama subskrypcja z jego powiadomieniem (restart raz).
      await loc.acquire(TrackRecorder.locationClient, title: 'Trening', text: 'y');
      expect(loc.active, isTrue);
      await loc.release('valkor_track');
      await loc.release(TrackRecorder.locationClient);
      expect(loc.active, isFalse);
      expect(loc.state, PhoneGps.off);
    });

    test('zatrzymana subskrypcja: restart po 12 s ciszy, z rosnącą przerwą', () async {
      await loc.acquire('valkor_track');
      ctrl.add(pos(50, 20, at(0)));
      await Future<void>.delayed(Duration.zero);
      loc.onPosition(pos(50, 20, at(1)), now: at(1));
      loc.tick(at(5));
      expect(loc.restarts, 0);
      loc.tick(at(7));
      expect(loc.state, PhoneGps.stale);
      expect(loc.reason(at(7)), contains('6 s'));
      loc.tick(at(14));
      await Future<void>.delayed(Duration.zero);
      expect(loc.restarts, 1);
      expect(loc.lastRestartReason, contains('brak pomiaru'));
      // Kolejny restart dopiero po dłuższej przerwie (backoff).
      loc.tick(at(20));
      await Future<void>.delayed(Duration.zero);
      expect(loc.restarts, 1);
      loc.tick(at(45));
      await Future<void>.delayed(Duration.zero);
      expect(loc.restarts, 2);
      // Pomiar wraca – stan dobry, przerwa zapisana.
      loc.onPosition(pos(50, 20, at(46)), now: at(46));
      expect(loc.state, PhoneGps.ok);
      expect(loc.maxGapSec, closeTo(45, 0.01));
      await loc.release('valkor_track');
    });

    test('wyłączony GPS: przyczyna w diagnostyce, bez subskrypcji', () async {
      GpsServices.serviceEnabled = () async => false;
      await loc.acquire('valkor_track');
      expect(subs, isEmpty);
      expect(loc.state, PhoneGps.serviceOff);
      expect(loc.reason(), contains('wyłączona'));
      await loc.release('valkor_track');
    });

    test('stary czas pomiaru telefonu nie jest nadpisywany chwilą odbioru', () {
      // Telefon oddaje po przerwie zapamiętaną pozycję sprzed 100 s.
      loc.onPosition(pos(50, 20, at(0)), now: at(100));
      expect(HandlerTrack.instance.last!.at, at(0));
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(100));
      expect(v.hasDistance, isFalse);
    });
  });

  group('Bluetooth i pakiety historyczne', () {
    test('zaległe pakiety po połączeniu uzupełniają historię, ale nie są „na żywo”', () async {
      c.markOpenedForTest(at(200));
      final got = <CollarFix>[];
      final sub = c.fixes.listen(got.add);
      // Kolejka trackera: pomiary sprzed 150, 145 i 140 s.
      for (var i = 0; i < 3; i++) {
        c.handleEvents([ev(north(i * 10.0), at(50 + i * 5), 100 + i)], now: at(201));
      }
      expect(c.diag.historical, 3);
      expect(c.dog!.lastHistorical!.historical, isTrue);
      expect(c.dog!.fix, isNull); // zaległe pomiary nie są pozycją na żywo
      expect(c.status(now: at(201)), isNot(DogLink.live));
      expect(c.diag.lags, isEmpty); // opóźnienia z kolejki nie psują statystyki
      // Pierwszy pomiar na żywo.
      c.handleEvents([ev(north(40), at(201), 200)], now: at(202));
      expect(c.status(now: at(202)), DogLink.live);
      expect(c.dog!.fix!.historical, isFalse);
      expect(c.diag.log.where((e) => e.historical), hasLength(3));
      expect(c.diag.csv().split('\n')[1], contains(';1;')); // kolumna „historyczny”
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got, hasLength(4));
    });

    test('opóźniony pakiet bez ponownego połączenia nadal odrzucony jako nieaktualny', () {
      c.markOpenedForTest(at(0));
      c.handleEvents([ev(north(0), at(100), 1)], now: at(400));
      expect(c.diag.rejected[FixReject.stale], 1);
    });

    test('odstępy odbioru Bluetooth liczone niezależnie od czasu pomiaru', () {
      for (var i = 0; i < 5; i++) {
        c.handleEvents([ev(north(0), at(i * 5), i + 1)], now: at(i * 5 + (i.isEven ? 1 : 3)));
      }
      final rx = c.diag.rxSpread!;
      expect(rx.min, 3);
      expect(rx.max, 7);
      expect(c.diag.intervalSpread!.min, 5);
    });

    test('błąd po zerwaniu połączenia: bez ponawiania, liczony osobno, kod czytelny', () async {
      c.state = CollarState.lost;
      var calls = 0;
      await expectLater(
          c.bleOp(() async {
            calls++;
            throw Exception('UniversalBleException: Code: UniversalBleErrorCode.deviceDisconnected, Message: x, Details: null');
          }, retries: 2),
          throwsException);
      expect(calls, 1);
      expect(c.diag.bleErrorsWhileDown, 1);
      expect(c.diag.bleErrorCodes['deviceDisconnected'], 1);
      expect(c.diag.lastBleError, isNot(contains('UniversalBleException')));
    });

    test('utrata Bluetooth: ostatnia znana pozycja i jej wiek zamiast „na żywo”', () {
      phone(north(0), 0);
      c.handleEvents([ev(north(30), at(0), 1)], now: at(1));
      c.state = CollarState.lost;
      for (var s = 1; s <= 20; s++) {
        phone(north(0), s);
      }
      final v = DistanceView.of(c, CollarLink.activeDog(), now: at(20));
      expect(v.state, DistanceState.lastKnown);
      expect(v.lastAgeSec, 20);
      expect(v.m, closeTo(30, 1));
      expect(v.sentence, startsWith('Ostatnio'));
    });

    test('prędkość psa: stara wartość nie jest pokazywana jako bieżąca', () {
      c.handleEvents([ev(north(0), at(0), 1, speedMs: 3)], now: at(1));
      expect(c.currentSpeedMs(CollarLink.activeDog(), now: at(2)), 3);
      expect(c.currentSpeedMs(CollarLink.activeDog(), now: at(30)), isNull);
    });
  });
}

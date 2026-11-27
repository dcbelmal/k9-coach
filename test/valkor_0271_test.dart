import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/app_version.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/field_test.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/dog_track_builder.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:k9_coach/gps/recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wersja 0.27.1: testy regresji do testów terenowych z firmware Valkor Track
/// 0.1.1 (SPORT, 1 Hz). Pakiety budowane jak w firmware (docs/PROTOKOL.md, rev 1.1).

final t0 = DateTime(2026, 11, 25, 18);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const _m = 111195.0;
double north(double m) => 50 + m / _m;

int _seq = 0;

Uint8List frame(int type, int flags, List<int> payload, {int mode = 0, int? seq}) {
  final b = BytesBuilder();
  final h = ByteData(16)
    ..setUint8(0, 0x56)
    ..setUint8(1, 1)
    ..setUint8(2, type)
    ..setUint8(3, flags)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, seq ?? ++_seq, Endian.little)
    ..setUint8(12, 0)
    ..setUint8(13, 1)
    ..setUint8(14, 1)
    ..setUint8(15, mode);
  b.add(h.buffer.asUint8List());
  b.add(payload);
  final body = b.toBytes();
  final c = valkorCrc16(body);
  return Uint8List.fromList([...body, c & 0xFF, c >> 8]);
}

int _fixId = 0;

/// Pozycja jak z firmware 0.1.1 (SPORT): dokładność 1,55 m, HDOP 0,5, 28 satelitów, fixId.
Uint8List position(double lat, DateTime fix,
    {bool historical = false,
    int age = 5,
    int? seq,
    int speedCmS = 150,
    bool valid = true,
    bool timeValid = true,
    int quality = 1,
    int accCm = 155,
    int hdop = 50,
    int sats = 28,
    bool stationary = false,
    int? fixId,
    int mode = 0}) {
  final d = ByteData(36);
  final utc = fix.toUtc().millisecondsSinceEpoch;
  d
    ..setUint32(0, timeValid ? utc ~/ 1000 : 0, Endian.little)
    ..setUint16(4, timeValid ? utc % 1000 : 0, Endian.little)
    ..setInt32(6, (lat * 1e7).round(), Endian.little)
    ..setInt32(10, (20 * 1e7).round(), Endian.little)
    ..setInt32(14, 10000, Endian.little)
    ..setUint16(18, speedCmS, Endian.little)
    ..setUint16(20, 0, Endian.little)
    ..setUint16(22, accCm, Endian.little)
    ..setUint16(24, hdop, Endian.little)
    ..setUint8(26, sats)
    ..setUint8(27, quality)
    ..setUint16(28, historical ? 0xFFFF : age, Endian.little)
    ..setUint16(30, 3990, Endian.little)
    ..setUint8(32, 84)
    ..setUint16(33, historical ? 0 : (fixId ?? ++_fixId), Endian.little);
  final flags = (valid ? ValkorFlags.fixValid : 0) |
      (timeValid ? ValkorFlags.timeValid : 0) |
      ValkorFlags.accEstimated |
      (historical ? ValkorFlags.historical : 0) |
      (stationary ? ValkorFlags.stationary : 0);
  return frame(1, flags, d.buffer.asUint8List(), seq: seq, mode: mode);
}

Uint8List status({int gnss = 2, int mode = 0}) {
  final st = ByteData(18)
    ..setUint32(0, 0xFFFFFFFF, Endian.little)
    ..setUint8(4, gnss)
    ..setUint16(8, 3990, Endian.little)
    ..setUint8(10, 84);
  return frame(2, 0, st.buffer.asUint8List(), mode: mode);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final r = TrackRecorder.instance;

  setUp(() async {
    _seq = 0;
    _fixId = 0;
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.valkorWriteOverride = (d) async {};
    c.writeOverride = (d) async {};
    c.sessionStart = at(-60);
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
    await PhoneLocation.instance.resetForTest();
    FieldTests.instance.resetForTest();
    AppState.instance.resetForTest();
    TrackRecorder.clock = () => at(100000);
  });
  tearDown(() async {
    r.state = RecState.idle;
    TrackRecorder.clock = DateTime.now;
    c.resetForTest();
    await PhoneLocation.instance.resetForTest();
  });

  /// Pozycje na żywo co 1 s (pełne sekundy GNSS, odbiór 5 ms później), pies idzie na północ [v] m/s.
  void live(num from, num to, {double v = 1.5, double startM = 0}) {
    for (var s = from; s <= to; s++) {
      c.handleValkor(position(north(startM + (s - from) * v), at(s)), now: at(s + 0.005));
    }
  }

  group('Protokół 1.1 (firmware 0.1.1)', () {
    test('fixId, dokładność z trackera, Perf i BuildInfo', () {
      final p = decodeValkor(position(north(0), at(1), fixId: 777)) as ValkorPosition;
      expect(p.fixId, 777);
      expect(p.accuracyM, closeTo(1.55, 1e-9));
      expect(p.fixValid, isTrue);
      expect(valkorToMesh(p).accuracyM, closeTo(1.55, 1e-9)); // nie HDOP × 3 m (= 1,5 m)
      final perf = ByteData(46)
        ..setUint32(0, 9000, Endian.little)
        ..setUint8(6, 1)
        ..setUint8(7, 10)
        ..setUint16(8, 1000, Endian.little)
        ..setUint16(12, 1001, Endian.little)
        ..setUint16(16, 5, Endian.little)
        ..setUint16(18, 0xFFFF, Endian.little)
        ..setInt16(40, 100, Endian.little)
        ..setUint16(42, 0xFFFF, Endian.little)
        ..setUint16(44, 0xFFFF, Endian.little);
      final pf = decodeValkor(frame(6, 0, perf.buffer.asUint8List())) as ValkorPerf;
      expect(pf.gnssIntMedianMs, 1000);
      expect(pf.latencyMedianMs, 5);
      expect(pf.lastFixAgeMs, isNull);
      expect(pf.tempC, 25);
      final bi = ByteData(46)
        ..setUint8(0, 1)
        ..setUint8(1, 1)
        ..setUint8(2, 0)
        ..setUint8(3, 1)
        ..setUint8(4, 1)
        ..setUint8(5, 1)
        ..setUint32(6, 12, Endian.little);
      final raw = bi.buffer.asUint8List();
      raw.setAll(10, '90c2717'.codeUnits);
      raw.setAll(24, 'Valkor Track 0.1.1a'.codeUnits);
      final b = decodeValkor(frame(7, 0, raw)) as ValkorBuildInfo;
      expect(b.protocol, '1.1');
      expect(b.firmware, '0.1.1');
      expect(b.buildId, 12);
      expect(b.commit, '90c2717');
      expect(b.name, 'Valkor Track 0.1.1a');
      c.handleValkor(frame(7, 0, raw), now: at(1));
      expect(c.valkor!.protocol, '1.1');
      expect(c.diag.csv(extra: c.valkor!.csvLines()), contains('valkor;firmware_commit;90c2717'));
    });
  });

  group('600 kolejnych pomiarów 1 Hz', () {
    test('każdy przyjęty, zawsze na żywo, jeden odcinek, dystans = rzeczywista droga', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 1; s <= 600; s++) {
        c.handleValkor(position(north(s * 1.5), at(s - 0.005)), now: at(s));
        expect(c.status(now: at(s + 0.5)), DogLink.live, reason: 'po $s s');
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(c.diag.accepted, 600);
      expect(c.valkor!.stats.live, 600);
      expect(c.valkor!.stats.lost, 0);
      expect(c.valkor!.stats.medianLiveInterval, closeTo(1, 0.01));
      expect(c.valkor!.stats.maxLiveGapSec, closeTo(1, 0.01));
      expect(r.dogTrack.samples, hasLength(600));
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(1));
      expect(r.dogMeters, closeTo(599 * 1.5, 2));
      expect(c.dog!.fix!.source, FixSource.valkor);
      expect(c.dog!.fix!.fixId, 600);
    });
  });

  group('Postój', () {
    test('identyczne współrzędne z nowym czasem: przyjęte, na żywo, bez dystansu', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 1; s <= 120; s++) {
        c.handleValkor(position(north(0), at(s - 0.005), speedCmS: 0, stationary: true), now: at(s));
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(c.diag.accepted, 120);
      expect(c.diag.rejected, isEmpty);
      expect(c.status(now: at(120.5)), DogLink.live);
      expect(r.dogMeters, 0);
      expect(r.dogPoints, hasLength(1));
      expect(c.diag.log.last.stationaryFlag, isTrue);
    });

    test('dryf GPS na postoju (±1,5 m) nie dodaje sztucznego dystansu', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      final rnd = math.Random(7);
      for (var s = 1; s <= 300; s++) {
        final noise = (rnd.nextDouble() - 0.5) * 3;
        c.handleValkor(position(north(noise), at(s - 0.005), speedCmS: 10), now: at(s));
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(r.dogMeters, lessThan(1));
      expect(c.diag.accepted, 300);
    });
  });

  group('Aktualność pozycji zależna od trybu', () {
    test('progi SPORT 3 / 5 / 10 s, WALK i ECO dłuższe', () {
      expect(FreshnessLimits.sport.classify(2.9), Freshness.live);
      expect(FreshnessLimits.sport.classify(4), Freshness.delayed);
      expect(FreshnessLimits.sport.classify(6), Freshness.stale);
      expect(FreshnessLimits.sport.classify(11), Freshness.noData);
      expect(FreshnessLimits.of(ValkorMode.search), FreshnessLimits.sport);
      expect(FreshnessLimits.of(ValkorMode.walk).classify(7), Freshness.live);
      expect(FreshnessLimits.of(ValkorMode.walk).classify(10), Freshness.delayed);
      expect(FreshnessLimits.of(ValkorMode.eco).classify(30), Freshness.live);
      expect(FreshnessLimits.of(ValkorMode.eco).classify(100), Freshness.noData);
    });

    test('zatrzymanie transmisji na 5, 10 i 30 s: opóźnienie, cisza kanału, ostrzeżenie; nowy odcinek trasy', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      live(1, 20);
      expect(c.liveLimitSec, 3);
      expect(c.status(now: at(22.9)), DogLink.live); // 2,9 s
      expect(c.status(now: at(24)), DogLink.delayed); // 4 s
      expect(c.freshness(now: at(24)), Freshness.delayed);
      // > 5 s bez pakietów: kanał Valkor niemy (Bluetooth nadal połączony).
      expect(c.status(now: at(26)), DogLink.valkorSilent);
      expect(c.freshness(now: at(26)), Freshness.stale);
      expect(c.freshness(now: at(31)), Freshness.noData); // > 10 s
      expect(c.currentSpeedMs('main', now: at(26)), isNull);
      // Ostatnia znana pozycja z czasem pomiaru zostaje.
      expect(c.lastKnown(CollarLink.activeDog())!.at.isAtSameMomentAs(at(20)), isTrue);
      // Wznowienie po 30 s: znowu na żywo, ale trasa nie łączy dziury.
      live(50, 60, startM: 45);
      await pumpEventQueue();
      await sub.cancel();
      expect(c.status(now: at(60.5)), DogLink.live);
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(2));
      // Pierwszy pomiar to stabilizacja (FixTrust: 2 spójne pomiary) – trasa od drugiego.
      expect(r.dogMeters, closeTo(18 * 1.5 + 10 * 1.5, 0.5));
      // Przerwa 5 s (krótsza niż próg) – jeden odcinek.
      final b = DogTrackBuilder(gapSec: FreshnessLimits.sport.trackGapSec);
      for (var s = 0; s < 10; s++) {
        b.add(DogSample(at(s), s.toDouble(), 0, north(s * 2.0), 20));
      }
      for (var s = 14; s < 20; s++) { // 5 s przerwy = próg – jeszcze ten sam odcinek
        b.add(DogSample(at(s), s.toDouble(), 0, north(s * 2.0), 20));
      }
      expect(b.segments, hasLength(1));
      b.add(DogSample(at(30), 30, 0, north(60), 20)); // 11 s przerwy
      expect(b.segments, hasLength(2));
    });

    test('Status z trackera „szukam satelitów” = utrata GNSS, nie Bluetooth', () {
      live(1, 5);
      for (var s = 6; s <= 12; s++) {
        c.handleValkor(status(gnss: 1), now: at(s + 0.5));
      }
      expect(c.status(now: at(12.6)), DogLink.gnssLost);
      final g = c.indicators(now: at(12.6)).firstWhere((i) => i.name == 'GNSS trackera');
      expect(g.level, IndicatorLevel.warn);
      final b = c.indicators(now: at(12.6)).first;
      expect(b.level, IndicatorLevel.ok); // Bluetooth działa
    });
  });

  group('Weryfikacja pomiarów', () {
    test('nieprawidłowy fix GNSS (flaga fixValid, jakość 0) jest odrzucany', () {
      c.handleValkor(position(north(0), at(1), valid: false), now: at(1.01));
      c.handleValkor(position(north(0), at(2), quality: 0), now: at(2.01));
      expect(c.dog?.fix, isNull);
      expect(c.diag.rejected[FixReject.invalid], 2);
      expect(c.diag.log.map((e) => e.verdict), everyElement('invalid'));
      c.handleValkor(position(north(0), at(3)), now: at(3.01));
      expect(c.dog!.fix, isNotNull);
    });

    test('nieznany czas pomiaru: czas odbioru wyraźnie oznaczony w CSV', () {
      c.handleValkor(position(north(0), at(1), timeValid: false), now: at(1.2));
      final f = c.dog!.fix!;
      expect(f.timeIsFix, isFalse);
      expect(f.fixAt, at(1.2));
      final e = c.diag.log.last;
      expect(e.timeSource, 'odbior');
      expect(e.gnssUtc, isNull);
    });

    test('czas UTC z trackera a czas lokalny: CSV w UTC, pozycja i trasa we właściwej chwili', () {
      c.handleValkor(position(north(0), at(1)), now: at(1.005));
      final e = c.diag.log.last;
      expect(e.gnssUtc!.isUtc, isTrue);
      expect(e.gnssUtc!.isAtSameMomentAs(at(1)), isTrue);
      final row = e.toCsv();
      expect(row, contains(at(1).toUtc().toIso8601String()));
      expect(row, contains(at(1.005).toUtc().toIso8601String()));
      expect(c.dog!.fix!.fixAt.isAtSameMomentAs(at(1)), isTrue);
      expect(e.timeSource, 'gnss');
      expect(e.gnssToBleMs, 5);
      expect(e.source, 'valkor');
      expect(e.valkorSeq, 1);
      expect(e.fixId, 1);
    });
  });

  group('Bluetooth i MTU', () {
    test('za małe MTU: wskaźnik, diagnostyka i CSV', () {
      c.handleValkor(status(), now: at(1));
      c.noteMtu(23, at: at(0.5));
      expect(c.diag.mtuOk, isFalse);
      final v = c.indicators(now: at(1.2)).firstWhere((i) => i.name == 'Valkor BLE');
      expect(v.level, IndicatorLevel.bad);
      expect(v.text, contains('23'));
      expect(c.diag.csv(), contains('bluetooth;mtu;23'));
      expect(c.diag.csv(), contains('bluetooth;mtu_negocjacja_udana;0'));
      c.noteMtu(247);
      expect(c.diag.mtuOk, isTrue);
      expect(c.valkor!.mtu, 247);
    });

    test('stany kanału: wykryty → subskrypcja → potwierdzony → odbiór pozycji → cisza', () {
      final v = c.valkor = ValkorSession(at(0));
      v.onDetected(at(0));
      expect(v.channel(at(0.5), delivering: false), ValkorChannel.detected);
      v.onSubscribed(at(1));
      expect(v.channel(at(2), delivering: false), ValkorChannel.subscribed);
      // Brak pakietu przez 6 s po subskrypcji: ponowienie inicjalizacji.
      expect(c.valkorReinitDue(at(4)), isNull);
      expect(c.valkorReinitDue(at(7.5)), isNotNull);
      expect(c.status(now: at(7.5)), DogLink.valkorSilent);
      c.handleValkor(status(), now: at(8));
      expect(v.channel(at(8.1), delivering: c.valkorDelivering(at(8.1))), ValkorChannel.confirmed);
      expect(c.valkorReinitDue(at(8.1)), isNull);
      live(9, 12);
      expect(v.channel(at(12.1), delivering: c.valkorDelivering(at(12.1))), ValkorChannel.receiving);
      expect(v.channel(at(20), delivering: c.valkorDelivering(at(20))), ValkorChannel.silent);
      expect(c.valkorReinitDue(at(20.5)), contains('brak pakietów'));
    });

    test('ponowne połączenie: subskrypcja od nowa, bez fałszywych utraconych pakietów, ponowienia ograniczone', () {
      live(1, 10);
      final v = c.valkor!;
      // Utrata Bluetooth.
      c.state = CollarState.lost;
      v.stats.resetLink();
      v.onDisconnected();
      expect(c.status(now: at(11)), DogLink.connecting);
      expect(c.valkorReinitDue(at(30)), isNull); // bez połączenia nic nie ponawiamy
      // Ponowne połączenie i subskrypcja; tracker numeruje dalej (pakiety niewysłane nie istnieją).
      c.state = CollarState.connected;
      v.onDetected(at(40));
      v.onSubscribed(at(40.2));
      _seq += 30;
      live(41, 45, startM: 50);
      expect(c.status(now: at(45.5)), DogLink.live);
      // Numeracja po ponownym połączeniu liczona od nowa: przerwa w łączności to nie utracone pakiety.
      expect(v.stats.lost, 0);
      expect(v.connections, 1);
      // Ponowienia inicjalizacji najwyżej 3 na połączenie.
      v.onDetected(at(50));
      v.onSubscribed(at(50));
      var n = 0;
      var t = 57.0;
      for (var i = 0; i < 10; i++) {
        final why = c.valkorReinitDue(at(t));
        if (why != null) {
          v.onReinit(at(t), why);
          n++;
        }
        t += 50;
      }
      expect(n, CollarLink.valkorMaxReinit);
    });
  });

  group('Historia po utracie zasięgu', () {
    test('historia w złej kolejności: wstawiona w trasę, bez duplikatów, poprawny dystans, bez wpływu na pozycję na żywo', () async {
      r.startClockForTest(at(0));
      final got = <CollarFix>[];
      final sub = c.fixes.listen((f) {
        got.add(f);
        r.onDogFix(f);
      });
      // 0–10 s na żywo, 11–39 s poza zasięgiem (tracker zapisuje), od 40 s znowu na żywo.
      for (var s = 0; s <= 10; s++) {
        c.handleValkor(position(north(s * 2.0), at(s)), now: at(s + 0.005));
      }
      for (var s = 40; s <= 45; s++) {
        c.handleValkor(position(north(s * 2.0), at(s)), now: at(s + 0.005));
      }
      await pumpEventQueue();
      final liveFix = c.dog!.fix!;
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(2)); // dziura przed odzyskaniem historii
      final hist = [for (var s = 11; s <= 39; s++) s]..shuffle(math.Random(3));
      for (final s in hist) {
        c.handleValkor(position(north(s * 2.0), at(s), historical: true), now: at(46));
      }
      // Duplikaty historii (np. ponowna synchronizacja).
      c.handleValkor(position(north(22.0), at(11), historical: true), now: at(46.5));
      // Pomiar z poprzedniego treningu i nieprawidłowy pomiar.
      // 0.27.3: „poprzednia sesja” = ponad 30 min przed startem aplikacji.
      c.handleValkor(position(north(0), at(-3000), historical: true), now: at(46.6));
      c.handleValkor(position(north(30), at(15.5), historical: true, sats: 2), now: at(46.7));
      await pumpEventQueue();
      await sub.cancel();
      expect(c.valkor!.historyRecovered, 29);
      expect(c.valkor!.historyDuplicates, 1);
      expect(c.valkor!.historyRejected, 2);
      expect(c.valkor!.historyBeforeLive, 29);
      // Bieżąca pozycja psa, prędkość i znacznik bez zmian.
      expect(c.dog!.fix, same(liveFix));
      expect(r.dogLast!.fixAt, liveFix.fixAt);
      expect(c.status(now: at(45.5)), DogLink.live);
      // Trasa: jeden ciągły odcinek w kolejności czasu, dystans 0 → 90 m.
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(1));
      final pts = r.dogPoints;
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i].t, greaterThanOrEqualTo(pts[i - 1].t));
        expect(pts[i].lat, greaterThan(pts[i - 1].lat));
      }
      // Pierwszy pomiar treningu to stabilizacja (FixTrust) – trasa od 1 s: 88 m.
      expect(r.dogMeters, closeTo(88, 0.5));
      expect(r.dogTrack.samples, hasLength(11 + 29 + 6));
      expect(got.where((f) => f.historical).every((f) => f.source == FixSource.valkorHistory), isTrue);
    });

    test('historia z czasu pauzy treningu nie trafia do trasy; brak historii = widoczna przerwa', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 0; s <= 10; s++) {
        c.handleValkor(position(north(s * 2.0), at(s)), now: at(s + 0.005));
      }
      await pumpEventQueue();
      r.pauseAtForTest(at(10.5));
      r.resumeAtForTest(at(30));
      for (var s = 31; s <= 35; s++) {
        c.handleValkor(position(north(s * 2.0), at(s)), now: at(s + 0.005));
      }
      await pumpEventQueue();
      for (var s = 11; s <= 29; s++) {
        c.handleValkor(position(north(s * 2.0), at(s), historical: true), now: at(36));
      }
      await pumpEventQueue();
      await sub.cancel();
      // Pauza dzieli trasę; pomiary z pauzy bez punktów i bez dystansu przez pauzę.
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(2));
      // Punkt trasy co ≥ 3 m (próg dryfu przy dokładności 1,55 m): 1 → 9 s = 16 m, 31 → 35 s = 8 m.
      expect(r.dogMeters, closeTo(16 + 8, 0.5));
      expect(r.dogTrack.samples.where((x) => x.t == null), hasLength(19)); // historia z pauzy bez czasu treningu
      expect(r.secondsAt(at(20)), isNull);
      expect(r.secondsAt(at(31)), closeTo(11.5, 0.01));
    });
  });

  group('Tryb awaryjny Meshtastic', () {
    MeshPositionEvent mesh(double lat, DateTime t, int id) =>
        MeshPositionEvent(1, MeshPosition(lat, 20, time: t, hdop: 0.6, sats: 20), packetId: id);

    test('podwójne pakiety Meshtastic/Valkor: bez duplikatów; fallback przy niemym kanale; powrót do Valkor', () {
      live(1, 10);
      // Kopia tego samego pomiaru przez Meshtastic – pomijana, gdy Valkor działa.
      c.handleEvents([mesh(north(13.5), at(10), 1)], now: at(10.5));
      expect(c.valkor!.meshIgnored, 1);
      expect(c.dog!.fix!.source, FixSource.valkor);
      // Kanał Valkor milknie przy działającym Bluetooth: pozycje Meshtastic przyjmowane, oznaczone.
      c.handleEvents([mesh(north(13.5), at(10), 2)], now: at(16)); // zaległa kopia tego samego pomiaru
      expect(c.dog!.fix!.source, FixSource.valkor); // ten sam pomiar – bez duplikatu
      c.handleEvents([mesh(north(40), at(30), 3)], now: at(30.4)); // pomiar dla bufora kanału
      expect(c.dog!.fix!.source, FixSource.meshtastic);
      expect(c.valkor!.meshFallback, 2);
      expect(c.status(now: at(31)), DogLink.live); // progi Meshtastic dla pozycji z Meshtastic
      final liveBefore = c.valkor!.stats.live;
      // Statystyki 1 Hz Valkor nie liczą pozycji Meshtastic.
      expect(liveBefore, 10);
      // Powrót kanału Valkor: znowu Valkor, kopie Meshtastic pomijane.
      live(31, 35, startM: 45);
      expect(c.dog!.fix!.source, FixSource.valkor);
      c.handleEvents([mesh(north(52.5), at(35), 4)], now: at(35.2));
      expect(c.valkor!.meshIgnored, 2);
      expect(c.diag.log.map((e) => e.source).toSet(), containsAll(['valkor', 'meshtastic']));
    });

    test('pakiety Valkor nie są pokazywane jako aktywność LoRa', () {
      live(1, 5);
      expect(c.dog!.lastHeard, isNull);
      expect(c.dog!.lastPacketAt, at(5.005));
      final lora = c.indicators(now: at(5.5)).last;
      expect(lora.name, 'LoRa');
      expect(lora.level, IndicatorLevel.na);
    });
  });

  group('Diagnostyka i sesje testowe', () {
    test('ponowne rozpoczęcie sesji diagnostycznej: liczniki od zera, osobne CSV', () {
      live(1, 10);
      final t1 = FieldTests.instance.start(FieldTestKind.standstill, notes: 'park; słonecznie', now: at(10.5));
      expect(c.valkor!.stats.packets, 0);
      live(11, 20, startM: 15);
      // Wyzerowanie liczników w trakcie: nowe okno.
      FieldTests.instance.resetCounters(now: at(20.5));
      live(21, 30, startM: 30);
      final done = FieldTests.instance.stop(now: at(30.5))!;
      expect(identical(done, t1), isTrue);
      final s = done.summary(c, now: at(40));
      expect(s.freshPositions, 10);
      expect(s.medianRxSec, closeTo(1, 0.01));
      expect(s.lossPct, 0);
      expect(s.meanAccuracyM, closeTo(1.55, 1e-6));
      expect(s.batteryEndPct, 84);
      final csv = done.csv(c, now: at(40));
      expect(csv, contains('test;rodzaj;postoj'));
      expect(csv, contains('test;warunki;park, słonecznie'));
      expect(csv, contains('podsumowanie_testu;swieze_pozycje;10'));
      expect(csv, contains('aplikacja;wersja;$appVersion'));
      // Drugi test – niezależny.
      FieldTests.instance.start(FieldTestKind.walk, now: at(40));
      live(41, 45, startM: 60);
      final t2 = FieldTests.instance.stop(now: at(45.5))!;
      expect(t2.summary(c, now: at(50)).freshPositions, 5);
      expect(FieldTests.instance.done, hasLength(2));
    });

    test('CSV: osobne liczniki sesji i firmware; gnss_pomiary_odrzucone w osobnych polach', () {
      final dg = ByteData(44)
        ..setUint32(0, 900, Endian.little)
        ..setUint32(4, 876, Endian.little)
        ..setUint32(8, 0, Endian.little);
      c.handleValkor(frame(4, 0, dg.buffer.asUint8List()), now: at(1));
      final dg2 = ByteData(44)
        ..setUint32(0, 910, Endian.little)
        ..setUint32(4, 886, Endian.little)
        ..setUint32(8, 1, Endian.little);
      c.handleValkor(frame(4, 0, dg2.buffer.asUint8List()), now: at(11));
      final csv = c.diag.csv(extra: c.valkor!.csvLines());
      expect(csv, contains('valkor_fw_od_startu;gnss_pomiary_wszystkie;886'));
      expect(csv, contains('valkor_fw_od_startu;gnss_pomiary_odrzucone;1'));
      expect(csv, contains('valkor_sesja;gnss_pomiary_wszystkie;10'));
      expect(csv, contains('valkor_sesja;gnss_pomiary_odrzucone;1'));
      expect(csv, isNot(contains('gnss_pomiary_odrzucone;886;')));
      expect(csv, contains('aplikacja;kompilacja;$appVersion+$appBuildNumber'));
    });

    test('stan aplikacji (pierwszy plan / tło) w dzienniku pomiarów', () {
      c.handleValkor(position(north(0), at(1)), now: at(1.005));
      expect(c.diag.log.last.appState, 'pierwszy_plan');
      AppState.instance.note(AppLifecycleState.paused, at: at(1.5));
      c.handleValkor(position(north(2), at(2)), now: at(2.005));
      expect(c.diag.log.last.appState, 'tlo');
      expect(AppState.instance.toBackground, 1);
      AppState.instance.note(AppLifecycleState.resumed, at: at(10));
      expect(AppState.instance.backgroundSec(at(20)), closeTo(8.5, 0.01));
      unawaited(Future<void>.value());
    });
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/distance_view.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/field_test.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:k9_coach/gps/recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wersja 0.27.2: testy regresyjne A–K ze specyfikacji „Poprawa wiarygodności
/// lokalizacji GNSS” (testy terenowe A–D z firmware 0.1.1, SPORT 1 Hz).
///
/// Uwaga: to są symulacje. Sprawdzają logikę aplikacji (co pokazujemy, kiedy
/// nie pokazujemy liczby, co trafia do trasy i CSV), NIE rzeczywistą
/// dokładność lokalizacji – tę potwierdza tylko test w terenie.

final t0 = DateTime(2026, 11, 26, 18);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const _m = 111195.0;
double north(double m) => 50 + m / _m;
double noise(int i, double amp) => amp * math.sin(i * 2.399) * math.cos(i * 0.731);

int _seq = 0;
int _fixId = 0;

Uint8List frame(int type, int flags, List<int> payload, {int mode = 0, int minor = 2}) {
  final b = BytesBuilder();
  final h = ByteData(16)
    ..setUint8(0, 0x56)
    ..setUint8(1, 1)
    ..setUint8(2, type)
    ..setUint8(3, flags)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, ++_seq, Endian.little)
    ..setUint8(12, 0)
    ..setUint8(13, 1)
    ..setUint8(14, minor)
    ..setUint8(15, mode);
  b.add(h.buffer.asUint8List());
  b.add(payload);
  final body = b.toBytes();
  final c = valkorCrc16(body);
  return Uint8List.fromList([...body, c & 0xFF, c >> 8]);
}

/// Pozycja jak z firmware 0.1.x: dokładność = HDOP × 3 m (flaga accEstimated).
Uint8List position(double lat, DateTime fix,
    {int speedCmS = 0, int hdop = 60, int sats = 20, int? accCm, bool stationary = false, int? fixId}) {
  final d = ByteData(36);
  final utc = fix.toUtc().millisecondsSinceEpoch;
  d
    ..setUint32(0, utc ~/ 1000, Endian.little)
    ..setUint16(4, utc % 1000, Endian.little)
    ..setInt32(6, (lat * 1e7).round(), Endian.little)
    ..setInt32(10, (20 * 1e7).round(), Endian.little)
    ..setInt32(14, 10000, Endian.little)
    ..setUint16(18, speedCmS, Endian.little)
    ..setUint16(20, 0, Endian.little)
    ..setUint16(22, accCm ?? hdop * 3, Endian.little)
    ..setUint16(24, hdop, Endian.little)
    ..setUint8(26, sats)
    ..setUint8(27, 1)
    ..setUint16(28, 5, Endian.little)
    ..setUint16(30, 3990, Endian.little)
    ..setUint8(32, 84)
    ..setUint16(33, fixId ?? ++_fixId, Endian.little);
  final flags = ValkorFlags.fixValid |
      ValkorFlags.timeValid |
      ValkorFlags.accEstimated |
      (stationary ? ValkorFlags.stationary : 0);
  return frame(1, flags, d.buffer.asUint8List());
}

Uint8List status({int gnss = 2}) {
  final st = ByteData(18)
    ..setUint32(0, 0xFFFFFFFF, Endian.little)
    ..setUint8(4, gnss)
    ..setUint16(8, 3990, Endian.little)
    ..setUint8(10, 84);
  return frame(2, 0, st.buffer.asUint8List());
}

Uint8List info({required bool detail, int minor = 2}) {
  final d = ByteData(24)
    ..setUint8(0, 1)
    ..setUint16(2, 0x1FF | (detail ? ValkorCap.fixDetail : 0), Endian.little)
    ..setUint16(4, 1000, Endian.little)
    ..setUint16(6, 360, Endian.little);
  final raw = d.buffer.asUint8List()..setAll(8, '2.7.15'.codeUnits);
  return frame(3, 0, raw, minor: minor);
}

Uint8List fixDetail(int fixId, double lat,
    {int flags = ValkorDetailFlags.rawAvailable | ValkorDetailFlags.rawMatches | ValkorDetailFlags.accFromHdop,
    int gga = 1,
    int sameRun = 0,
    int gapMs = 1000,
    int jumpCm = 0,
    int? gstCm,
    int recoverAge = 0xFF,
    int sats = 20,
    int hdop = 60}) {
  final d = ByteData(40)
    ..setUint16(0, fixId, Endian.little)
    ..setInt32(2, (lat * 1e7).round(), Endian.little)
    ..setInt32(6, (20 * 1e7).round(), Endian.little)
    ..setUint8(10, gga)
    ..setUint8(11, 'A'.codeUnitAt(0))
    ..setUint16(12, flags | (gstCm != null ? ValkorDetailFlags.gstValid : 0), Endian.little)
    ..setUint16(14, gstCm ?? 0xFFFF, Endian.little)
    ..setUint16(16, gstCm ?? 0xFFFF, Endian.little)
    ..setUint16(18, sameRun, Endian.little)
    ..setUint32(20, gapMs, Endian.little)
    ..setUint32(24, jumpCm, Endian.little)
    ..setUint8(28, recoverAge)
    ..setUint8(29, 0xFF)
    ..setUint8(30, 0xFF)
    ..setUint8(31, sats)
    ..setUint16(32, 0, Endian.little)
    ..setUint16(34, hdop, Endian.little);
  return frame(8, 0, d.buffer.asUint8List());
}

Uint8List gnssStats({int reason = 2, int maxGapMs = 50000, int notDelivered = 0}) {
  final d = ByteData(46)
    ..setUint32(0, 12000, Endian.little)
    ..setUint32(4, 3000, Endian.little)
    ..setUint32(8, 50, Endian.little)
    ..setUint32(12, notDelivered, Endian.little)
    ..setUint32(16, 3, Endian.little)
    ..setUint32(20, 40, Endian.little)
    ..setUint16(24, 1, Endian.little)
    ..setUint32(26, maxGapMs, Endian.little)
    ..setUint8(30, reason)
    ..setUint8(31, 1)
    ..setUint32(32, 20544, Endian.little)
    ..setUint32(36, 12, Endian.little)
    ..setUint16(40, 1, Endian.little)
    ..setUint16(42, 65, Endian.little)
    ..setUint16(44, 3, Endian.little);
  return frame(9, 0, d.buffer.asUint8List());
}

Position pos(double lat, DateTime t, {double acc = 4, double speed = 0}) => Position(
      latitude: lat,
      longitude: 20,
      timestamp: t,
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final loc = PhoneLocation.instance;
  final r = TrackRecorder.instance;
  final writes = <Uint8List>[];

  void phone(double lat, num s, {double acc = 4, double speed = 0}) =>
      loc.onPosition(pos(lat, at(s), acc: acc, speed: speed), now: at(s));
  void dog(double lat, num s, {int hdop = 60, int sats = 20, int speedCmS = 0, int? accCm}) =>
      c.handleValkor(position(lat, at(s), hdop: hdop, sats: sats, speedCmS: speedCmS, accCm: accCm),
          now: at(s + 0.005));
  DistanceView view(num s) => DistanceView.of(c, CollarLink.activeDog(), now: at(s));
  void rssi(int dbm, num s) {
    c.diag.bleRssi = dbm;
    c.diag.bleRssiAt = at(s);
  }

  setUp(() async {
    _seq = 0;
    _fixId = 0;
    writes.clear();
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.valkorWriteOverride = (d) async => writes.add(Uint8List.fromList(d));
    c.writeOverride = (d) async {};
    c.sessionStart = at(-60);
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
    await loc.resetForTest();
    FieldTests.instance.resetForTest();
    DogAlerts.instance.resetForTest();
    TrackRecorder.clock = () => at(100000);
  });
  tearDown(() async {
    r.state = RecState.idle;
    TrackRecorder.clock = DateTime.now;
    c.resetForTest();
    await loc.resetForTest();
  });

  group('A – pies 10 cm od telefonu', () {
    test('błąd obu GPS 5–8 m: „Pies w pobliżu” albo brak liczby, nigdy „6 m”', () {
      final shown = <DistanceState>{};
      for (var s = 0; s <= 120; s++) {
        // Telefon i obroża w tym samym miejscu; każdy GPS ma własny, wolno
        // zmienny błąd 3–6 m (jak w teście A: 30 cm pokazane jako 5–8 m).
        phone(north(3 + noise(s, 1)), s, acc: 5);
        dog(north(-3 + noise(s + 40, 1)), s, hdop: 90);
        if (s < 20) continue;
        final v = view(s + 0.5);
        shown.add(v.state);
        expect(v.state, isNot(DistanceState.estimate), reason: 'po $s s: ${v.text} ${v.m}');
      }
      expect(shown, contains(DistanceState.nearby));
    });
  });

  group('B – mieszkanie, dryf GPS w budynku', () {
    test('dryf do 59 m z „prędkością” 3 m/s: bez metrów, bez alarmu smyczy, bez dystansu trasy', () async {
      final got = <DogAlert>[];
      final a = DogAlerts.instance..onAlert = got.add;
      await a.save(AlertSettings(enabled: true, leashM: 20, lowBattery: null));
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 0; s <= 180; s++) {
        phone(north(0), s, acc: 8);
        // HDOP 4–6, 5 satelitów, pozycja błądzi do ~59 m.
        final drift = 30 + 29 * math.sin(s / 9);
        dog(north(drift), s, hdop: 450 + (s % 3) * 50, sats: 5, speedCmS: 295);
        a.check(now: at(s + 0.5));
        if (s >= 5) {
          final v = view(s + 0.5);
          expect(v.state, isNot(DistanceState.estimate), reason: 'po $s s: ${v.text}');
          expect(v.state, isNot(DistanceState.nearby), reason: 'po $s s');
        }
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(c.dog!.fix!.gnssState, GnssState.weak);
      expect(got.where((e) => e.kind == AlertKind.leash), isEmpty);
      expect(r.dogMeters, lessThan(5));
      a.onAlert = null;
      await a.save(AlertSettings());
    });
  });

  group('C/D – stabilnie zła pozycja, potem korekta', () {
    test('189 m przez 37 s przy silnym Bluetooth: „Podejrzana pozycja GPS”, bez liczby i alarmu', () async {
      final got = <DogAlert>[];
      final a = DogAlerts.instance..onAlert = got.add;
      await a.save(AlertSettings(enabled: true, leashM: 20, lowBattery: null));
      // Najpierw poprawne pozycje, pies przy nodze.
      for (var s = 0; s <= 30; s++) {
        phone(north(0), s);
        rssi(-48, s);
        dog(north(0.5 + noise(s, 0.5)), s, hdop: 60);
      }
      expect(view(30.5).state, DistanceState.nearby);
      // Odbiornik „przeskakuje” na 189 m i trzyma tę pozycję, HDOP nadal dobry.
      for (var s = 31; s <= 68; s++) {
        phone(north(0), s);
        rssi(-48, s);
        dog(north(185 + noise(s, 2)), s, hdop: 70);
        a.check(now: at(s + 0.5));
        final v = view(s + 0.5);
        expect(v.hasDistance, isFalse, reason: 'po $s s: ${v.text}');
        expect(v.text, isNot(contains('18')), reason: 'po $s s: ${v.text}');
      }
      expect(view(68.5).state, DistanceState.suspect);
      expect(view(68.5).bleConflict, isTrue);
      expect(got.where((e) => e.kind == AlertKind.leash), isEmpty);
      expect(c.diag.log.last.bleConflict, isTrue);
      a.onAlert = null;
      await a.save(AlertSettings());
    });

    test('korekta 178 m w 1 s przy 0,03 m/s: nowy odcinek trasy, skok nie dodaje dystansu', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 0; s <= 40; s++) {
        phone(north(0), s);
        dog(north(189 + noise(s, 1)), s, speedCmS: 3);
      }
      for (var s = 41; s <= 80; s++) {
        phone(north(0), s);
        dog(north(11 + noise(s, 1)), s, speedCmS: 3);
      }
      await pumpEventQueue();
      await sub.cancel();
      final corr = c.diag.log.where((e) => e.correction == true).toList();
      expect(corr, isNotEmpty);
      expect(corr.first.jumpM!, closeTo(178, 4));
      expect(r.dogMeters, lessThan(30), reason: 'skok 178 m nie jest drogą psa');
      expect(r.dogSegments.where((s) => s.isNotEmpty).length, greaterThanOrEqualTo(2));
      // Surowe dane zostają w dzienniku bez zmian.
      expect(c.diag.log.where((e) => e.lat > north(150)), isNotEmpty);
    });

    test('po korekcie 10 cm od psa: nie „10–12 m ± 2 m”', () {
      for (var s = 0; s <= 40; s++) {
        phone(north(0), s, acc: 5);
        dog(north(189), s);
      }
      final shown = <String>[];
      for (var s = 41; s <= 100; s++) {
        phone(north(noise(s, 1)), s, acc: 5);
        // Po korekcie GPS obroży wciąż ma błąd ~10 m.
        dog(north(10 + noise(s + 3, 1.5)), s, hdop: 120);
        final v = view(s + 0.5);
        if (v.state == DistanceState.estimate) {
          // Jeśli już pokazujemy liczbę, to z uczciwą niepewnością.
          expect(v.uncertaintyM!, greaterThanOrEqualTo(4.5), reason: 'po $s s: ${v.text}');
        }
        shown.add(v.text);
      }
      expect(shown.any((t) => t.contains('± 2 m') || t.contains('±2 m')), isFalse);
    });
  });

  group('E – identyczne współrzędne', () {
    test('firmware 0.1.2: FixDetail z serią identycznych surowych pozycji – „zatrzymana”, większa niepewność', () {
      c.handleValkor(info(detail: true), now: at(0));
      for (var s = 1; s <= 40; s++) {
        phone(north(0), s);
        final id = s;
        c.handleValkor(position(north(25), at(s), hdop: 450, sats: 5, fixId: id), now: at(s + 0.005));
        c.handleValkor(
            fixDetail(id, north(25),
                sameRun: s, hdop: 450, sats: 5, flags: ValkorDetailFlags.rawAvailable | ValkorDetailFlags.rawMatches | ValkorDetailFlags.rawSame),
            now: at(s + 0.01));
      }
      final a = c.dog!.assessment!;
      expect(a.frozen, isTrue);
      expect(a.sameRun, greaterThanOrEqualTo(10));
      expect(a.sigmaM, greaterThan(13.5 + 5)); // HDOP × 3 m plus kara za zamrożenie
      final e = c.diag.log.last;
      expect(e.frozen, isTrue);
      expect(e.detail, isNotNull);
      expect(e.detail!.sameRawRun, 40);
      final header = FixLogEntry.csvHeader.split(';');
      final row = e.toCsv().split(';');
      expect(row[header.indexOf('pozycja_zatrzymana')], '1');
      expect(row[header.indexOf('fw_identyczne_surowe')], '40');
      expect(row[header.indexOf('zrodlo_niepewnosci_psa')], 'hdop');
    });

    test('postój na zewnątrz z dobrym GPS: identyczne współrzędne to NIE awaria', () {
      for (var s = 1; s <= 60; s++) {
        phone(north(0), s);
        dog(north(1), s, hdop: 50, sats: 25);
      }
      expect(c.dog!.assessment!.frozen, isFalse);
      expect(c.dog!.fix!.gnssState, GnssState.reliable);
      expect(view(60.5).state, DistanceState.nearby);
    });
  });

  group('F – przerwa 50 s', () {
    test('kolejne fix_id, ale 50 s bez pomiaru: „brak nowej pozycji”, potem odzyskanie i stabilizacja', () {
      for (var s = 0; s <= 30; s++) {
        phone(north(0), s);
        dog(north(40), s);
      }
      expect(view(30.5).state, DistanceState.estimate);
      c.handleValkor(status(gnss: 1), now: at(35));
      for (var s = 31; s <= 80; s++) {
        phone(north(0), s);
      }
      expect(c.status(now: at(80)), isNot(DogLink.live));
      // Ostatnia znana pozycja – wyraźnie podpisana, bez alarmu odległości.
      expect(view(80).state, DistanceState.lastKnown);
      expect(view(80).alarmable, isFalse);
      expect(view(80).sentence, startsWith('Ostatnia znana pozycja'));
      c.handleValkor(gnssStats(reason: 2, maxGapMs: 50000), now: at(80));
      expect(c.valkor!.gnssStats!.reasonCsv, 'odbiornik_bez_fixu');
      dog(north(40), 81);
      final a = c.dog!.assessment!;
      expect(a.gapSec, closeTo(51, 0.1)); // ostatni pomiar 30 s, następny 81 s
      expect(a.recovering, isTrue);
      expect(view(81.5).hasDistance, isFalse, reason: view(81.5).text);
      // Po kolejnych dobrych pomiarach (≥ 10 s) znów liczba.
      for (var s = 82; s <= 100; s++) {
        phone(north(0), s);
        dog(north(40), s);
      }
      expect(view(100.5).state, DistanceState.estimate);
      expect(view(100.5).m, closeTo(40, 2));
      expect(c.diag.log.any((e) => (e.gapSec ?? 0) > 49), isTrue);
    });
  });

  group('G – wyjście z budynku', () {
    test('słaby → stabilizacja → wiarygodny; bez liczby w trakcie stabilizacji', () {
      final states = <GnssState>[];
      for (var s = 0; s <= 20; s++) {
        phone(north(0), s);
        dog(north(30 + noise(s, 8)), s, hdop: 500, sats: 5);
      }
      states.add(c.dog!.fix!.gnssState!);
      for (var s = 21; s <= 50; s++) {
        phone(north(0), s);
        dog(north(30 + noise(s, 0.5)), s, hdop: 70, sats: 18);
        if (s == 23) {
          states.add(c.dog!.fix!.gnssState!);
          expect(view(s + 0.5).hasDistance, isFalse, reason: view(s + 0.5).text);
        }
      }
      states.add(c.dog!.fix!.gnssState!);
      expect(states, [GnssState.weak, GnssState.stabilizing, GnssState.reliable]);
      expect(view(50.5).state, DistanceState.estimate);
    });
  });

  group('H/I – prawdziwy ruch', () {
    test('bieg 6 m/s do 100 m: bez fałszywej korekty, dystans trasy = droga', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      rssi(-80, 0);
      for (var s = 0; s <= 20; s++) {
        phone(north(0), s);
        dog(north(1), s);
      }
      for (var s = 21; s <= 37; s++) {
        phone(north(0), s);
        dog(north(1 + (s - 20) * 6.0), s, speedCmS: 600);
      }
      for (var s = 38; s <= 60; s++) {
        phone(north(0), s);
        dog(north(103), s);
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(c.diag.log.where((e) => e.correction == true), isEmpty);
      expect(r.dogMeters, closeTo(102, 6));
      final v = view(60.5);
      expect(v.state, DistanceState.estimate);
      expect(v.m, closeTo(103, 2));
    });

    test('pies naprawdę 100 m dalej, słaby Bluetooth: bez fałszywego „podejrzana pozycja”', () {
      for (var s = 0; s <= 40; s++) {
        phone(north(0), s);
        rssi(-88, s);
        dog(north(100 + noise(s, 1)), s);
      }
      final v = view(40.5);
      expect(v.state, DistanceState.estimate);
      expect(v.bleConflict, isFalse);
      expect(v.m, closeTo(100, 3));
    });

    test('Bluetooth nie zeruje i nie przycina odległości: 40 m przy RSSI −60', () {
      for (var s = 0; s <= 40; s++) {
        phone(north(0), s);
        rssi(-60, s);
        dog(north(40), s);
      }
      final v = view(40.5);
      expect(v.state, DistanceState.estimate);
      expect(v.m, closeTo(40, 2));
    });
  });

  group('J – zgodność i ponowne połączenie', () {
    bool sentSetDetail() => writes.any((w) => w.length >= 5 && w[2] == ValkorCmd.setDetail && w[4] == 1);

    test('firmware 0.1.1 (bez FixDetail): komenda SetDetail NIE jest wysyłana, wszystko działa', () async {
      c.handleValkor(info(detail: false, minor: 1), now: at(0));
      await pumpEventQueue();
      expect(sentSetDetail(), isFalse);
      for (var s = 1; s <= 30; s++) {
        phone(north(0), s);
        dog(north(40), s);
      }
      expect(view(30.5).state, DistanceState.estimate);
      expect(c.diag.log.last.detail, isNull);
    });

    test('firmware 0.1.2: SetDetail po Info, ponownie po ponownym połączeniu', () async {
      c.handleValkor(info(detail: true), now: at(0));
      await pumpEventQueue();
      expect(sentSetDetail(), isTrue);
      writes.clear();
      c.handleValkor(info(detail: true), now: at(1));
      await pumpEventQueue();
      expect(sentSetDetail(), isFalse, reason: 'raz na połączenie');
      final v = c.valkor!;
      c.state = CollarState.lost;
      v.onDisconnected();
      c.state = CollarState.connected;
      v.onDetected(at(40));
      v.onSubscribed(at(40.2));
      c.handleValkor(info(detail: true), now: at(41));
      await pumpEventQueue();
      expect(sentSetDetail(), isTrue);
    });

    test('FixDetail i GnssStats: dekodowanie i dopięcie do wiersza CSV o tym samym fix_id', () {
      final d = decodeValkor(fixDetail(7, north(3), gstCm: 300, sameRun: 4, gapMs: 1200, jumpCm: 150)) as ValkorFixDetail;
      expect(d.fixId, 7);
      expect(d.rawLat, closeTo(north(3), 1e-7));
      expect(d.gstHorizontalM, closeTo(math.sqrt(18), 1e-9));
      expect(d.sameRawRun, 4);
      expect(d.gapMs, 1200);
      expect(d.jumpCm, 150);
      expect(d.staticThr, isNull);
      final g = decodeValkor(gnssStats()) as ValkorGnssStats;
      expect(g.historyOverwritten, 20544);
      expect(g.maxGapMs, 50000);
      expect(g.reasonCsv, 'odbiornik_bez_fixu');
      c.handleValkor(info(detail: true), now: at(0));
      phone(north(0), 1);
      c.handleValkor(position(north(3), at(1), fixId: 9), now: at(1.005));
      c.handleValkor(fixDetail(9, north(3), gstCm: 300), now: at(1.01));
      final e = c.diag.log.last;
      expect(e.fixId, 9);
      expect(e.detail!.fixId, 9);
      expect(e.sigmaSource, isNotNull);
      final header = FixLogEntry.csvHeader.split(';');
      final row = e.toCsv().split(';');
      expect(row, hasLength(header.length));
      for (final col in [
        'lat_filtr_aplikacji',
        'niepewnosc_psa_m',
        'niepewnosc_telefonu_m',
        'stan_gnss_psa',
        'korekta_pozycji',
        'pozycja_zatrzymana',
        'niespojnosc_gnss_ble',
        'wyswietlony_stan',
        'podejrzane_urzadzenie',
        'fw_lat_przed_filtracja',
        'fw_gst_lat_m',
      ]) {
        expect(header, contains(col));
      }
      expect(double.parse(row[header.indexOf('fw_gst_lat_m')]), 3.0);
    });
  });

  group('K – 600 pomiarów 1 Hz z oceną jakości', () {
    test('każdy przyjęty, jeden odcinek, ocena „wiarygodna”, bez korekt', () async {
      r.startClockForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var s = 1; s <= 600; s++) {
        phone(north(0), s);
        dog(north(s * 1.5), s, speedCmS: 150);
        expect(c.status(now: at(s + 0.5)), DogLink.live, reason: 'po $s s');
      }
      await pumpEventQueue();
      await sub.cancel();
      expect(c.diag.accepted, 600);
      expect(c.dog!.fix!.gnssState, GnssState.reliable);
      expect(c.diag.log.where((e) => e.correction == true), isEmpty);
      expect(r.dogSegments.where((s) => s.isNotEmpty), hasLength(1));
      expect(r.dogMeters, closeTo(599 * 1.5, 3));
    });
  });
}

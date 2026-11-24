import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/fix_filter.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy z pierwszego testu terenowego T1000-E (jeden moduł, Bluetooth):
/// pies na smyczy 3 m, pozycje opóźnione 15–30 s, postój i dryf,
/// powtórzone pakiety, utrata Bluetooth, złe znaczniki czasu.

final t0 = DateTime(2026, 11, 24, 12);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
int epoch(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;

/// Pozycja jak z firmware Meshtastic: time (4) = wysłanie, timestamp (7) = pomiar,
/// ground_speed (15) km/h, ground_track (16) stopnie × 1e5, HDOP (12) × 100.
List<int> meshPosition(double lat, double lng,
    {DateTime? fix, DateTime? sent, int? kmh, double? course, int? hdop, int? sats, int? seq}) {
  final w = PbWriter()
    ..fixed32(1, (lat * 1e7).round() & 0xffffffff)
    ..fixed32(2, (lng * 1e7).round() & 0xffffffff);
  if (sent != null) w.fixed32(4, epoch(sent));
  if (fix != null) w.fixed32(7, epoch(fix));
  if (hdop != null) w.varint(12, hdop);
  if (kmh != null) w.varint(15, kmh);
  if (course != null) w.varint(16, (course * 1e5).round());
  if (sats != null) w.varint(19, sats);
  if (seq != null) w.varint(22, seq);
  return w.toBytes();
}

List<int> fromRadioPacket(int from, int port, List<int> payload, {int? requestId}) {
  final data = PbWriter()
    ..varint(1, port)
    ..bytes(2, payload);
  if (requestId != null) data.fixed32(6, requestId);
  final pk = PbWriter()
    ..fixed32(1, from)
    ..fixed32(2, 0xffffffff)
    ..bytes(4, data.toBytes())
    ..fixed32(6, 77);
  return (PbWriter()..bytes(2, pk.toBytes())).toBytes();
}

MeshPosition pos(double lat, double lng, DateTime fix, {double? speedMs, double? hdop, int? seq, bool timeIsFix = true}) =>
    MeshPosition(lat, lng, time: fix, timeIsFix: timeIsFix, speedMs: speedMs, hdop: hdop, seq: seq);

/// Punkt [m] metrów na północ od (50, 20).
double north(double m) => 50 + m / 111195.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Dekodowanie pozycji Meshtastic', () {
    test('czas pomiaru z pola timestamp, osobno czas wysłania; prędkość km/h → m/s; kierunek; HDOP', () {
      final fix = at(0), sent = at(14);
      final ev = decodeFromRadio(fromRadioPacket(
          9, MeshPort.position, meshPosition(50, 20, fix: fix, sent: sent, kmh: 18, course: 271.5, hdop: 120, sats: 9, seq: 5),
          requestId: 1234));
      final e = ev.single as MeshPositionEvent;
      final p = e.position;
      expect(p.time, fix);
      expect(p.sentTime, sent);
      expect(p.timeIsFix, isTrue);
      expect(p.speedMs, closeTo(5.0, 1e-9)); // 18 km/h = 5 m/s
      expect(p.courseDeg, closeTo(271.5, 1e-6));
      expect(p.hdop, 1.2);
      expect(p.accuracyM, closeTo(6.0, 1e-9)); // HDOP × 5 m
      expect(p.sats, 9);
      expect(p.seq, 5);
      expect(e.requestId, 1234);
      expect(e.packetId, 77);
    });

    test('opóźnienie widać: pomiar sprzed 15 s nie udaje świeżego', () {
      final f = FixFilter(1).check(pos(50, 20, at(0)), at(15)).fix!;
      expect(f.fixAt, at(0));
      expect(f.lagSec, 15);
      expect(f.timeIsFix, isTrue);
    });

    test('ustawienia z FromRadio.config i odpowiedzi administracyjnej', () {
      final position = (PbWriter()
            ..varint(1, 15)
            ..varint(5, 8)
            ..varint(7, 811))
          .toBytes();
      final lora = (PbWriter()
            ..varint(1, 1)
            ..varint(7, 3))
          .toBytes();
      final cfg = (PbWriter()
            ..bytes(2, position)
            ..bytes(6, lora))
          .toBytes();
      final ev = decodeFromRadio((PbWriter()..bytes(5, cfg)).toBytes());
      expect(ev.whereType<MeshConfigEvent>().map((e) => e.section), [2, 6]);
      final admin = (PbWriter()..bytes(6, (PbWriter()..bytes(2, position)).toBytes())).toBytes();
      final ev2 = decodeFromRadio(fromRadioPacket(9, MeshPort.admin, admin));
      expect((ev2.single as MeshConfigEvent).section, 2);
    });
  });

  group('Pies na smyczy 3 m, pozycje opóźnione', () {
    setUp(() => HandlerTrack.instance.clear());

    test('odległość z dopasowaniem czasu: kilka metrów zamiast ~26 m', () {
      final h = HandlerTrack.instance;
      // Przewodnik idzie na północ 1,3 m/s, telefon podaje pozycję co sekundę.
      for (var s = 0; s <= 40; s++) {
        h.add(HandlerFix(at(s), north(1.3 * s), 20, accuracyM: 4));
      }
      // Pies 2 m za przewodnikiem; pomiar z 20. sekundy dociera w 40. sekundzie.
      final dog = CollarFix(1, north(1.3 * 20 - 2), 20, at(20), receivedAt: at(40), accuracyM: 5, speedMs: 1.3);
      final d = DogDistance.of(dog, h, now: at(40))!;
      expect(d.matchedM, closeTo(2, 0.5));
      expect(d.currentM, closeTo(28, 0.5)); // stara metoda: pies „28 m z tyłu”
      expect(d.ageSec, 20);
      expect(d.bestM, d.matchedM);
      expect(d.withinError, isTrue); // 2 m < błąd GPS ~6,4 m
      expect(fmtDistance(d.bestM!, d.bestUncertaintyM), startsWith('<'));
    });

    test('bez historii telefonu z chwili pomiaru – odległość bieżąca z dużą niepewnością', () {
      final h = HandlerTrack.instance..add(HandlerFix(at(40), north(52), 20, accuracyM: 4));
      final dog = CollarFix(1, north(24), 20, at(20), receivedAt: at(40), accuracyM: 5);
      final d = DogDistance.of(dog, h, now: at(40))!;
      expect(d.matchedM, isNull);
      expect(d.currentM, closeTo(28, 0.5));
      // 20 s × co najmniej 1,5 m/s – pies mógł być w innym miejscu.
      expect(d.currentUncertaintyM, greaterThan(30));
      expect(d.withinError, isTrue);
    });

    test('przerwa w pomiarach telefonu: pozycja nie jest „trzymana” minutami', () {
      final h = HandlerTrack.instance..add(HandlerFix(at(0), 50, 20, accuracyM: 4, speedMs: 0));
      // Telefon stał (prędkość 0): pozycja trzymana krótko, z zapasem.
      expect(h.at(at(1))!.accuracyM, 4);
      expect(h.at(at(10))!.accuracyM, 7);
      expect(h.at(at(10))!.gapSec, 10);
      expect(h.at(at(25)), isNull);
      // Telefon szedł: niepewność rośnie z prędkością, po 10 s pozycja nieaktualna.
      h.add(HandlerFix(at(100), north(10), 20, accuracyM: 4, speedMs: 1.5));
      expect(h.at(at(30)), isNull); // w długiej przerwie – brak pozycji
      expect(h.at(at(99))!.lat, north(10));
      expect(h.at(at(106))!.accuracyM, closeTo(13, 0.01));
      expect(h.at(at(112)), isNull);
    });

    test('formatowanie: zaokrąglenie do błędu, bez fałszywej precyzji', () {
      expect(fmtDistance(3.4, 7), '< 7 m');
      expect(fmtDistance(37.6, 7.2), '38 m ± 7 m');
      expect(fmtDistance(123, 9), '125 m ± 9 m');
      expect(fmtDistance(1530, 12), '1,5 km ± 12 m');
    });
  });

  group('Postój i dryf GPS', () {
    test('dryf ±5 m przy HDOP 1 i prędkości 0 nie jest ruchem', () {
      final f = FixFilter(1);
      final jitter = [0.0, 4.0, -3.5, 5.0, -4.5, 2.0, 6.5, -6.0];
      var moved = 0;
      for (final (i, m) in jitter.indexed) {
        final v = f.check(pos(north(m), 20, at(i * 5), speedMs: 0, hdop: 1), at(i * 5 + 1)).fix!;
        if (i > 0 && v.moved) moved++;
      }
      expect(moved, 0);
    });

    test('bez prędkości i dokładności: dryf do 8 m to postój, marsz to ruch', () {
      expect(FixFilter.isDrift(6, null, null), isTrue);
      expect(FixFilter.isDrift(12, null, null), isFalse);
      // Tracker mówi „idę 5 km/h” – krótkie przesunięcie to ruch.
      expect(FixFilter.isDrift(4, 6, 1.6), isFalse);
      // Tracker mówi „stoję” – nawet przesunięcie 10 m przy błędzie 6 m to dryf.
      expect(FixFilter.isDrift(10, 6, 0), isTrue);
      expect(FixFilter.isDrift(13, 6, 0), isFalse);
    });

    test('dawny błąd: prędkość km/h brana jako m/s – 1 km/h nie jest już ruchem', () {
      final ev = decodeFromRadio(fromRadioPacket(1, MeshPort.position, meshPosition(50, 20, fix: at(0), kmh: 1)));
      final p = (ev.single as MeshPositionEvent).position;
      expect(p.speedMs, lessThan(0.5));
    });
  });

  group('Powtórzone pakiety i złe znaczniki czasu', () {
    test('ten sam pakiet – duplikat; ten sam pomiar GPS w nowym pakiecie – powtórzony', () {
      final f = FixFilter(1);
      expect(f.check(pos(50, 20, at(0), seq: 1), at(2), packetId: 11).accepted, isTrue);
      expect(f.check(pos(50, 20, at(0), seq: 1), at(3), packetId: 11).reject, FixReject.duplicate);
      // Firmware wysyła ten sam pomiar drugi raz (nowy pakiet, ten sam timestamp).
      final again = MeshPosition(50, 20, time: at(0), sentTime: at(10), seq: 1);
      expect(f.check(again, at(10), packetId: 12).reject, FixReject.repeated);
    });

    test('regresja: identyczne współrzędne i seq = 1, ale nowy czas GPS – nowy pomiar (postój)', () {
      final f = FixFilter(1);
      for (var i = 0; i < 5; i++) {
        final v = f.check(pos(50, 20, at(i * 5), seq: 1, hdop: 0.6), at(i * 5 + 1), packetId: 100 + i);
        expect(v.accepted, isTrue, reason: 'pomiar $i');
        expect(v.fix!.fixAt, at(i * 5));
        if (i > 0) expect(v.fix!.moved, isFalse);
      }
    });

    test('powtórzony pakiet ze starym czasem GPS nie odświeża aktualności', () {
      final f = FixFilter(1);
      f.check(pos(50, 20, at(10)), at(11), packetId: 1);
      expect(f.check(pos(50, 20, at(5)), at(20), packetId: 2).reject, FixReject.outOfOrder);
      expect(f.last!.fixAt, at(10));
    });

    test('zegar trackera bez GPS (różnica > 10 min) – czas odbioru, oznaczony jako nieznany', () {
      final f = FixFilter(1).check(pos(50, 20, DateTime(2000)), at(5)).fix!;
      expect(f.fixAt, at(5));
      expect(f.timeIsFix, isFalse);
    });

    test('tylko czas wysłania (stary firmware / bez flagi) – oznaczony, większa niepewność', () {
      HandlerTrack.instance
        ..clear()
        ..add(HandlerFix(at(0), 50, 20, accuracyM: 4));
      final f = FixFilter(1).check(pos(north(20), 20, at(1), timeIsFix: false), at(1)).fix!;
      expect(f.timeIsFix, isFalse);
      final d = DogDistance.of(f, HandlerTrack.instance, now: at(1))!;
      expect(d.matchedUncertaintyM, greaterThan(DogDistance.unknownTimeM));
    });

    test('pakiety w złej kolejności odrzucone', () {
      final f = FixFilter(1);
      f.check(pos(50, 20, at(10)), at(11));
      expect(f.check(pos(50, 20, at(5)), at(12)).reject, FixReject.outOfOrder);
    });
  });

  group('Diagnostyka', () {
    test('seq stale 1 (Meshtastic) – liczba zgubionych pakietów nieznana; rosnąca numeracja – liczona', () {
      final d = CollarDiagnostics();
      for (var i = 0; i < 10; i++) {
        d.addSeq(1);
      }
      expect(d.seqReliable, isFalse);
      expect(d.missingSeq, isNull);
      final d2 = CollarDiagnostics();
      for (final s in [1, 2, 3, 4, 5, 6, 8, 9, 10]) {
        d2.addSeq(s);
      }
      expect(d2.missingSeq, 1);
    });

    test('opóźnienia, odstępy, postoje i eksport CSV', () {
      final c = CollarLink.instance..resetForTest();
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([const MeshMyInfo(1)], now: at(0));
      for (var i = 0; i < 4; i++) {
        final fix = at(i * 15);
        c.handleEvents([MeshPositionEvent(1, MeshPosition(north(i < 2 ? 0 : 30.0), 20, time: fix, seq: 1, hdop: 1), packetId: 50 + i)],
            now: fix.add(const Duration(seconds: 9)));
      }
      final d = c.diag;
      expect(d.missingSeq, isNull);
      expect(d.still, 2); // pomiar 2 (postój) i 4 (blisko 3.)
      expect(d.lagSpread!.avg, 9);
      expect(d.intervalSpread!.min, 15);
      expect(d.accepted, 4);
      expect(d.log, hasLength(4));
      final all = d.csv().split('\n');
      final csv = all.takeWhile((l) => l.isNotEmpty).toList();
      expect(csv.first, FixLogEntry.csvHeader);
      expect(csv, hasLength(5));
      expect(all, contains('zdarzenie_bluetooth;czas;szczegoly'));
      expect(csv[1], contains(';9.0;')); // opóźnienie 9 s
      c.resetForTest();
    });
  });

  group('Zapytania o pozycję (limit firmware 3 min) i utrata Bluetooth', () {
    late CollarLink c;
    setUp(() {
      c = CollarLink.instance..resetForTest();
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([const MeshMyInfo(1)], now: at(0));
      c.markOpenedForTest(at(0));
    });
    tearDown(() => c.resetForTest());

    test('pierwsze zapytanie po połączeniu, kolejne nie częściej niż co 3 min', () {
      expect(c.positionRequestDue(at(1)), isNull);
      expect(c.positionRequestDue(at(3)), 1);
      c.diag.lastRequestAt = at(3);
      expect(c.positionRequestDue(at(60)), isNull);
      expect(c.positionRequestDue(at(184)), 1);
    });

    test('świeże pozycje przychodzą same – bez zapytań', () {
      c.handleEvents([MeshPositionEvent(1, pos(50, 20, at(10)))], now: at(12));
      expect(c.positionRequestDue(at(30)), isNull);
      expect(c.positionRequestDue(at(150)), isNull);
      expect(c.positionRequestDue(at(195)), 1); // pomiar starszy niż 3 min
    });

    test('odpowiedź na zapytanie jest liczona', () {
      c.writeOverride = (_) async {};
      final ev = decodeFromRadio(fromRadioPacket(1, MeshPort.position, meshPosition(50, 20, fix: at(5)), requestId: 99));
      c.handleEvents(ev, now: at(6));
      expect(c.diag.requestReplies, 0); // nie nasze zapytanie
      expect(c.diag.accepted, 1);
    });

    test('po utracie Bluetooth pozycja przestaje być „na żywo”, po powrocie wraca', () {
      c.handleEvents([MeshPositionEvent(1, pos(50, 20, at(10)))], now: at(11));
      expect(c.status(now: at(12)), DogLink.live);
      c.state = CollarState.lost;
      expect(c.status(now: at(20)), DogLink.connecting);
      c.state = CollarState.connected;
      expect(c.status(now: at(200)), DogLink.stale);
      c.handleEvents([MeshPositionEvent(1, pos(50, 20.0001, at(201)))], now: at(203));
      expect(c.status(now: at(204)), DogLink.live);
    });
  });

  group('Ustawienia trackera i profile trybów', () {
    Uint8List posCfg({int broadcast = 30, int gps = 8, int flags = 811}) => (PbWriter()
          ..varint(1, broadcast)
          ..varint(4, 1) // gps_enabled (przestarzałe) – musi zostać
          ..varint(5, gps)
          ..varint(7, flags)
          ..varint(13, 1))
        .toBytes();
    Uint8List loraCfg({int preset = 0}) => (PbWriter()
          ..varint(1, 1)
          ..varint(2, preset)
          ..varint(7, 3) // EU_868
          ..varint(8, 3)
          ..varint(9, 1))
        .toBytes();

    TrackerConfig cfg({int broadcast = 30, int gps = 8, int preset = 0}) => TrackerConfig()
      ..position = posCfg(broadcast: broadcast, gps: gps)
      ..lora = loraCfg(preset: preset)
      ..device = (PbWriter()..varint(1, 0)).toBytes();

    test('LONG_FAST w UE: limit radia ~10 s niezależnie od ustawień', () {
      final c = cfg(broadcast: 5, gps: 2);
      expect(c.radioMinSec, closeTo(10, 0.01));
      expect(c.expectedIntervalSec, 10);
      expect(c.limitReason, contains('LONG_FAST'));
      expect(cfg(broadcast: 30, gps: 8).expectedIntervalSec, 30);
      expect(cfg(broadcast: 5, gps: 2, preset: 6).expectedIntervalSec, 5);
    });

    test('profil sportowy: zmiany, zachowane inne pola, oczekiwany odstęp 5 s', () {
      final c = cfg();
      final p = TrackerProfile.sport;
      expect(p.diff(c).map((d) => d.$1), hasLength(3)); // rozgłaszanie, GPS, preset
      final b = PbFields.parse(p.positionBytes(c));
      expect(b.integer(1), 5);
      expect(b.integer(5), 2);
      expect(b.integer(7), 811);
      expect(b.integer(4), 1);
      expect(b.integer(13), 1);
      final l = PbFields.parse(p.loraBytes(c)!);
      expect(l.integer(2), 6);
      expect(l.integer(7), 3);
      expect(p.expectedSec(c), 5);
      // Spacerowy nie zmienia presetu radia.
      expect(TrackerProfile.walk.loraBytes(c), isNull);
    });

    test('zapis profilu: set_config do trackera i sprawdzenie po ponownym odczycie', () async {
      final c = CollarLink.instance..resetForTest();
      final sent = <Uint8List>[];
      c.writeOverride = (d) async => sent.add(d);
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([
        const MeshMyInfo(1),
        MeshConfigEvent(2, posCfg()),
        MeshConfigEvent(6, loraCfg()),
        const MeshConfigComplete(1),
      ]);
      expect(c.trackerMatchesMode, isFalse);
      await c.setMode(TrackMode.sport);
      expect(await c.applyProfile(TrackerProfile.sport), isNull);
      expect(sent, hasLength(2)); // lora + position
      // ToRadio.packet → Data(port ADMIN) → AdminMessage.set_config(34) → Config.position(2)
      final pkt = PbFields.parse(sent.last).message(1)!;
      expect(pkt.integer(2), 1);
      final data = pkt.message(4)!;
      expect(data.integer(1), MeshPort.admin);
      final cfgMsg = PbFields.parse(data.raw(2)!).message(34)!;
      expect(cfgMsg.message(2)!.integer(1), 5);
      expect(c.applyState, ProfileApply.waiting);

      // Odczyt ustawień, który nie jest naszym odczytem po zapisie – nic nie potwierdza.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.handleEvents([MeshConfigEvent(2, posCfg(broadcast: 5, gps: 2)), const MeshConfigComplete(2)]);
      expect(c.applyState, ProfileApply.waiting);

      // Nasz odczyt po zapisie: tracker podaje stare ustawienia – zmiana się nie zapisała.
      final id1 = await c.verifyRead();
      c.handleEvents([MeshConfigEvent(2, posCfg()), MeshConfigComplete(id1)]);
      expect(c.applyState, ProfileApply.failed);
      expect(c.applyError, isNotNull);

      // Drugie podejście – tracker podaje nowe ustawienia.
      await c.applyProfile(TrackerProfile.sport);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final id2 = await c.verifyRead();
      c.handleEvents([
        MeshConfigEvent(2, posCfg(broadcast: 5, gps: 2)),
        MeshConfigEvent(6, loraCfg(preset: 6)),
        MeshConfigComplete(id2),
      ]);
      expect(c.applyState, ProfileApply.verified);
      expect(c.trackerMatchesMode, isTrue);
      expect(c.expectedIntervalSec, 5);
      c.resetForTest();
    });

    test('przy dwóch modułach nie zmieniamy ustawień urządzenia w kieszeni', () async {
      final c = CollarLink.instance..resetForTest();
      c.writeOverride = (_) async {};
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([
        const MeshMyInfo(1),
        const MeshNodeInfo(2, longName: 'Pies', hwModel: hwT1000E),
        MeshConfigEvent(2, posCfg()),
      ]);
      expect(c.direct, isFalse);
      expect(c.expectedIntervalSec, isNull);
      expect(await c.applyProfile(TrackerProfile.sport), isNotNull);
      c.resetForTest();
    });
  });

  group('Alarmy: smycz z dopasowaniem czasu', () {
    test('pies obok przewodnika, pozycja sprzed 25 s – brak alarmu smyczy 10 m', () {
      HandlerTrack.instance.clear();
      final e = AlertEngine(AlertSettings(enabled: true, leashM: 10, lowBattery: null));
      final h = HandlerTrack.instance;
      for (var s = 0; s <= 60; s++) {
        h.add(HandlerFix(at(s), north(1.5 * s), 20, accuracyM: 4));
      }
      final got = <AlertKind>[];
      for (final s in [30, 45, 60]) {
        final fix = CollarFix(1, north(1.5 * (s - 25) - 2), 20, at(s - 25), receivedAt: at(s), accuracyM: 5);
        final now = at(s);
        got.addAll(e
            .evaluate(AlertInput(
                now: now,
                link: DogLink.live,
                fix: fix,
                handler: LatLng(north(1.5 * s), 20),
                distance: DogDistance.of(fix, h, now: now)))
            .map((a) => a.kind));
      }
      expect(got, isEmpty);
    });

    test('pies naprawdę daleko – alarm po 2 pomiarach', () {
      HandlerTrack.instance.clear();
      final e = AlertEngine(AlertSettings(enabled: true, leashM: 10, lowBattery: null));
      final h = HandlerTrack.instance;
      for (var s = 0; s <= 60; s++) {
        h.add(HandlerFix(at(s), 50, 20, accuracyM: 4));
      }
      final got = <AlertKind>[];
      for (final s in [30, 45]) {
        final fix = CollarFix(1, north(60), 20, at(s - 20), receivedAt: at(s), accuracyM: 5);
        got.addAll(e
            .evaluate(AlertInput(now: at(s), link: DogLink.live, fix: fix, distance: DogDistance.of(fix, h, now: at(s))))
            .map((a) => a.kind));
      }
      expect(got, [AlertKind.leash]);
    });
  });
}

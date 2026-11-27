import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/field_test.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// Wersja 0.27.3: testy regresyjne po teście terenowym 27.11.2026
/// (Bluetooth wyłączony i włączony w telefonie, naturalna utrata zasięgu,
/// historia po restarcie aplikacji).
///
/// To są symulacje logiki aplikacji bez prawdziwego Bluetooth. Nie zastępują
/// testu z trackerem: czas odzyskania połączenia i kompletność historii na
/// urządzeniu potwierdza tylko test w terenie.

final t0 = DateTime(2026, 11, 27, 15);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
double north(double m) => 50 + m / 111195.0;

int _seq = 0;
int _fixId = 0;

Uint8List frame(int type, int flags, List<int> payload) {
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
    ..setUint8(14, 2)
    ..setUint8(15, 0);
  b.add(h.buffer.asUint8List());
  b.add(payload);
  final body = b.toBytes();
  final c = valkorCrc16(body);
  return Uint8List.fromList([...body, c & 0xFF, c >> 8]);
}

Uint8List position(double lat, DateTime fix, {bool historical = false, int sats = 20, int hdop = 60}) {
  final d = ByteData(36);
  final utc = fix.toUtc().millisecondsSinceEpoch;
  d
    ..setUint32(0, utc ~/ 1000, Endian.little)
    ..setUint16(4, utc % 1000, Endian.little)
    ..setInt32(6, (lat * 1e7).round(), Endian.little)
    ..setInt32(10, (20 * 1e7).round(), Endian.little)
    ..setInt32(14, 10000, Endian.little)
    ..setUint16(18, 100, Endian.little)
    ..setUint16(22, hdop * 3, Endian.little)
    ..setUint16(24, hdop, Endian.little)
    ..setUint8(26, sats)
    ..setUint8(27, 1)
    ..setUint16(28, historical ? 0xFFFF : 5, Endian.little)
    ..setUint16(30, 3990, Endian.little)
    ..setUint8(32, 84)
    ..setUint16(33, historical ? 0 : ++_fixId, Endian.little);
  final flags = ValkorFlags.fixValid |
      ValkorFlags.timeValid |
      ValkorFlags.accEstimated |
      (historical ? ValkorFlags.historical : 0);
  return frame(1, flags, d.buffer.asUint8List());
}

Uint8List ack(int command, int value) => frame(5, 0, [command, 0, value, 0]);

Uint8List linkStats({int unsent = 120, int inflight = 40, int rssi = -88}) {
  final d = ByteData(40)
    ..setUint16(0, unsent, Endian.little)
    ..setUint16(2, inflight, Endian.little)
    ..setUint16(4, 360, Endian.little)
    ..setUint32(6, 52, Endian.little)
    ..setUint32(10, 3, Endian.little)
    ..setUint32(14, 0, Endian.little)
    ..setUint32(18, 0, Endian.little)
    ..setUint32(22, 1, Endian.little)
    ..setUint32(26, 2, Endian.little)
    ..setInt8(30, rssi)
    ..setInt8(31, -95)
    ..setInt8(32, 0) // średnia niedostępna
    ..setUint8(33, 1)
    ..setUint16(34, 4, Endian.little)
    ..setUint32(36, 75, Endian.little);
  return frame(10, 0, d.buffer.asUint8List());
}

Position pos(double lat, DateTime t, {double acc = 4}) => Position(
      latitude: lat,
      longitude: 20,
      timestamp: t,
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final writes = <Uint8List>[];

  void dog(double lat, num s) => c.handleValkor(position(lat, at(s)), now: at(s + 0.005));
  void hist(double lat, num fixS, num rxS) => c.handleValkor(position(lat, at(fixS), historical: true), now: at(rxS));

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
    await PhoneLocation.instance.resetForTest();
    HandlerTrack.instance.clear();
    FieldTests.instance.resetForTest();
  });
  tearDown(() async {
    FieldTests.instance.resetForTest();
    c.resetForTest();
    await PhoneLocation.instance.resetForTest();
  });

  group('LinkRecovery – decyzje strażnika (czysta logika)', () {
    test('cisza ponad próg: najpierw ponowna subskrypcja, po 4 s bez pakietu pełne ponowne połączenie', () {
      RecoveryAction d(num now, {DateTime? resubAt, int resubs = 0}) => LinkRecovery.decide(
          now: at(now), valkor: true, since: at(0), silentSec: 3, resubscribedAt: resubAt, resubscribes: resubs);
      expect(d(3.5), RecoveryAction.none);
      expect(d(4.1), RecoveryAction.resubscribe);
      expect(d(5, resubAt: at(4.1), resubs: 1), RecoveryAction.none);
      expect(d(8.2, resubAt: at(4.1), resubs: 1), RecoveryAction.reconnect);
    });

    test('nieudana subskrypcja na martwym połączeniu (po wyłączeniu Bluetooth): od razu ponowne połączenie', () {
      expect(
          LinkRecovery.decide(now: at(2.5), valkor: true, since: at(0), silentSec: 3, subscribeFailed: true),
          RecoveryAction.reconnect);
    });

    test('5 nieudanych odczytów z rzędu (kanał Meshtastic): ponowne połączenie', () {
      expect(LinkRecovery.decide(now: at(0), valkor: false, silentSec: 3, readFails: 5), RecoveryAction.reconnect);
      expect(LinkRecovery.decide(now: at(0), valkor: false, silentSec: 3, readFails: 4), RecoveryAction.none);
    });

    test('odstępy ponawiania: 1, 2, 3, 5, 8 s, po 5 min co 15 s, po 15 min co 30 s', () {
      final r = LinkRecovery()..onLost(at(0), 'test');
      final first = [for (var i = 0; i < 7; i++) r.nextDelay(at(10)).inSeconds];
      expect(first, [1, 2, 3, 5, 8, 8, 8]);
      expect(r.nextDelay(at(301)).inSeconds, 15);
      expect(r.nextDelay(at(901)).inSeconds, 30);
      r.resetBackoff();
      expect(r.nextDelay(at(10)).inSeconds, 1);
    });

    test('przerwa: czas do Bluetooth i do pierwszej pozycji, łączny czas bez pozycji, CSV', () {
      final r = LinkRecovery()
        ..onLost(at(0), 'utrata zasięgu')
        ..onAttempt()
        ..onConnectFailed('deviceNotFound')
        ..onAttempt()
        ..onConnectFailed('gatt133')
        ..onAttempt()
        ..onConnected(at(6.5));
      expect(r.needScan, isTrue);
      r.onLost(at(7), 'drugie zgłoszenie tej samej przerwy');
      r.onLivePosition(at(8));
      r.onHistoryDone(at(12));
      expect(r.records, hasLength(1));
      final rec = r.records.single;
      expect(rec.why, 'utrata zasięgu');
      expect(rec.attempts, 3);
      expect(rec.bleSec, 6.5);
      expect(rec.positionSec, 8);
      expect(rec.historySec, 12);
      expect(r.noPositionSec, 8);
      final csv = r.csvLines();
      expect(csv, contains('odzyskiwanie;bledy_133;1'));
      expect(csv, contains('odzyskiwanie;urzadzenie_nie_znalezione;1'));
      expect(csv.last, contains(';utrata zasięgu;3;6.5;8.0;12.0'));
    });
  });

  group('Bluetooth w telefonie wyłączony i włączony (test 27.11: 329 s „połączony” bez pozycji)', () {
    test('wyłączenie: koniec stanu „połączony”, brak prób łączenia; włączenie: łączenie zaplanowane od razu', () {
      c.wantedForTest = true;
      dog(north(5), 1);
      expect(c.status(now: at(1.5)), DogLink.live);
      c.onAdapterState(AvailabilityState.poweredOff, now: at(2));
      expect(c.state, CollarState.lost);
      expect(c.recovery.adapterOff, isTrue);
      expect(c.retryPending, isFalse, reason: 'bez prób, gdy Bluetooth jest wyłączony');
      // Nigdy „aktywne śledzenie” bez aktualnych pozycji.
      expect(c.status(now: at(3)), isNot(DogLink.live));
      final bt = c.indicators(now: at(3)).first;
      expect(bt.text, 'wyłączony w telefonie');
      expect(c.recovery.current, isNotNull, reason: 'przerwa w pozycjach liczona od wyłączenia');
      c.onAdapterState(AvailabilityState.poweredOn, now: at(20));
      expect(c.recovery.adapterOff, isFalse);
      expect(c.retryPending, isTrue);
      expect(c.recovery.adapterOffEvents, 1);
      expect(c.diag.bleEvents.map((e) => e.kind), containsAllInOrder([BleEvent.adapterOff, BleEvent.adapterOn]));
    });

    test('pierwsza pozycja po odzyskaniu kończy przerwę bez restartu aplikacji', () {
      c.wantedForTest = true;
      dog(north(5), 1);
      c.onAdapterState(AvailabilityState.poweredOff, now: at(2));
      c.onAdapterState(AvailabilityState.poweredOn, now: at(10));
      // Ponowne połączenie (symulacja: to, co robi _openInner po sukcesie).
      c.state = CollarState.connected;
      c.recovery.onConnected(at(12));
      c.valkor!
        ..onDetected(at(12))
        ..onSubscribed(at(12.2));
      dog(north(6), 13);
      expect(c.status(now: at(13.2)), DogLink.live);
      expect(c.recovery.current, isNull);
      expect(c.recovery.records.single.positionSec, closeTo(11, 0.1));
    });
  });

  group('Bluetooth połączony bez transmisji (kanał Valkor milczy)', () {
    test('pokazany jako „połączony bez transmisji”, potem ponowna subskrypcja, potem pełne ponowne połączenie', () {
      c.wantedForTest = true;
      final v = c.valkor ??= ValkorSession(at(0));
      v
        ..onDetected(at(0))
        ..onSubscribed(at(0.2));
      for (var s = 1; s <= 10; s++) {
        dog(north(5), s);
      }
      expect(c.recoveryActionDue(at(10.5)), RecoveryAction.none);
      final silent = c.valkorLimits.channelSilentSec;
      final t1 = 10 + silent + 1.2;
      expect(c.indicators(now: at(t1)).first.text, 'połączony bez transmisji');
      expect(c.status(now: at(t1)), isNot(DogLink.live));
      expect(c.recoveryActionDue(at(t1)), RecoveryAction.resubscribe);
      expect(c.recovery.current, isNotNull, reason: 'przerwa liczona od ostatniego pakietu');
      expect(c.recovery.current!.lostAt, at(10.005));
      v.onReinit(at(t1), 'test');
      expect(c.recoveryActionDue(at(t1 + 2)), RecoveryAction.none);
      expect(c.recoveryActionDue(at(t1 + 4.1)), RecoveryAction.reconnect);
    });

    test('błąd subskrypcji po ponownym połączeniu: pełne ponowne połączenie po 2 s, nie 3 próby subskrypcji', () {
      final v = c.valkor ??= ValkorSession(at(0));
      v
        ..onDetected(at(0))
        ..onSubscribeError(at(0.3), 'GATT_ERROR');
      expect(c.recoveryActionDue(at(1)), RecoveryAction.none);
      expect(c.recoveryActionDue(at(2.1)), RecoveryAction.reconnect);
    });

    test('Bluetooth rozłączony / łączenie: strażnik nic nie robi (nie ma równoległych prób)', () {
      final v = c.valkor ??= ValkorSession(at(0));
      v.onDetected(at(0));
      c.state = CollarState.lost;
      expect(c.recoveryActionDue(at(60)), RecoveryAction.none);
      c.state = CollarState.connecting;
      expect(c.recoveryActionDue(at(60)), RecoveryAction.none);
    });
  });

  group('Historia', () {
    test('po restarcie aplikacji: pomiary z ostatnich 30 min przyjęte, starsze odrzucone z przyczyną', () {
      // Aplikacja uruchomiona ponownie w t=0, tracker pracował cały czas.
      c.sessionStart = at(0);
      for (var s = -600; s < 0; s += 2) {
        hist(north(10), s, 2);
      }
      hist(north(10), -2000, 2.5);
      final v = c.valkor!;
      expect(v.historyRecovered, 300);
      expect(v.historyRejectReasons['poprzednia_sesja'], 1);
      expect(v.historyRejected, 1);
    });

    test('historia po przerwie 30 / 60 / 120 / 300 s: kompletna, bez duplikatów, nie nadpisuje pozycji na żywo', () {
      for (final gap in [30, 60, 120, 300]) {
        c.resetForTest();
        c.deviceId = 'x';
        c.state = CollarState.connected;
        c.valkorWriteOverride = (d) async => writes.add(Uint8List.fromList(d));
        c.writeOverride = (d) async {};
        c.sessionStart = at(-60);
        c.handleEvents([const MeshMyInfo(1)], now: at(0));
        for (var s = 0; s <= 10; s++) {
          dog(north(1), s);
        }
        // Przerwa [gap] s, tracker zapisuje co 2 s; po powrocie najpierw pozycja na żywo.
        final back = 10 + gap;
        dog(north(50), back);
        final v = c.valkor!..onHistoryRequested(at(back + 0.1));
        final n = gap ~/ 2;
        c.handleValkor(ack(ValkorCmd.syncHistory, n), now: at(back + 0.2));
        for (var i = 0; i < n; i++) {
          hist(north(1.0 + i), 11 + 2 * i, back + 0.3 + i * 0.01);
          dog(north(50), back + 0.3 + i * 0.01); // ta sama pozycja na żywo w trakcie (przeplatane)
        }
        expect(v.historyDoneDue(at(back + 1)), isTrue, reason: 'przerwa $gap s');
        v.onHistoryDone(at(back + 1));
        expect(v.historyComplete, isTrue, reason: 'przerwa $gap s');
        expect(v.historyRecovered, n, reason: 'przerwa $gap s');
        expect(v.historyDuplicates, 0);
        // Najnowsza pozycja to wciąż pozycja na żywo.
        final f = c.dog!.fix!;
        expect(f.historical, isFalse);
        expect(f.lat, closeTo(north(50), 1e-6));
      }
    });

    test('pomiar ponowiony przez tracker po zerwaniu (już odebrany na żywo): odrzucony jako duplikat z przyczyną', () {
      for (var s = 1; s <= 5; s++) {
        dog(north(1), s);
      }
      hist(north(1), 4, 20);
      hist(north(1), 5, 20.1);
      hist(north(1), 5, 20.2); // drugi raz w historii
      hist(north(1), 6, 20.3); // nowy
      final v = c.valkor!;
      expect(v.historyRecovered, 1);
      expect(v.historyDuplicates, 3);
      expect(v.historyRejectReasons['juz_odebrany_na_zywo'], 3);
      expect(c.dog!.fix!.historical, isFalse);
    });

    test('rozłączenie w trakcie pobierania: stan wraca do „nie pobrano”, po ponownym połączeniu pobranie od nowa', () {
      final v = c.valkor ??= ValkorSession(at(0));
      v.onHistoryRequested(at(1));
      c.handleValkor(ack(ValkorCmd.syncHistory, 200), now: at(1.1));
      for (var i = 0; i < 50; i++) {
        hist(north(1), -400 + 2 * i, 1.2 + i * 0.01);
      }
      expect(v.historySync, HistorySync.receiving);
      v.onDisconnected();
      expect(v.historySync, HistorySync.idle);
      expect(v.historyComplete, isNull);
      v.onHistoryRequested(at(30));
      c.handleValkor(ack(ValkorCmd.syncHistory, 150), now: at(30.1));
      for (var i = 50; i < 200; i++) {
        hist(north(1), -400 + 2 * i, 30.2 + i * 0.01);
      }
      expect(v.historyDoneDue(at(33)), isTrue);
      v.onHistoryDone(at(33));
      expect(v.historyComplete, isTrue);
      expect(v.historyRecovered, 200);
      expect(v.historyDuplicates, 0);
    });

    test('Ack 0: nic do pobrania, stan „pobrano” od razu', () {
      final v = c.valkor ??= ValkorSession(at(0));
      v.onHistoryRequested(at(1));
      c.handleValkor(ack(ValkorCmd.syncHistory, 0), now: at(1.1));
      expect(v.historySync, HistorySync.done);
    });

    test('pomiar historyczny ze słabym GNSS: odrzucony z przyczyną, nie po cichu', () {
      c.handleValkor(position(north(1), at(-30), historical: true, sats: 2), now: at(1));
      final v = c.valkor!;
      expect(v.historyRejected, 1);
      expect(v.historyRejectReasons.keys.single, isNotEmpty);
      expect(v.csvLines().any((l) => l.startsWith('valkor_sesja;historia_odrzucona_wg_przyczyny;') && l.contains('=1')),
          isTrue);
    });
  });

  group('LinkStats (firmware 0.1.2 po 27.11)', () {
    test('dekodowanie: stan bufora, przyczyny, RSSI 0 = niedostępne', () {
      final l = decodeValkor(linkStats()) as ValkorTrackerLink;
      expect(l.historyUnsent, 120);
      expect(l.historyInflight, 40);
      expect(l.historyCapacity, 360);
      expect(l.historyRestored, 52);
      expect(l.liveFailedStored, 3);
      expect(l.queueFull, 1);
      expect(l.notifyErrors, 2);
      expect(l.rssiNow, -88);
      expect(l.rssiMin, -95);
      expect(l.rssiAvg, isNull);
      expect(l.syncActive, isTrue);
      expect(l.connects, 4);
      expect(l.connectedS, 75);
    });

    test('CSV: pola trackera, a bez pakietu jawne „niedostepne”', () {
      final v = c.valkor ??= ValkorSession(at(0));
      expect(v.csvLines(), contains('valkor_fw_lacze;pakiet_linkstats;niedostepne'));
      c.handleValkor(linkStats(rssi: 0), now: at(1));
      final csv = v.csvLines();
      expect(csv, contains('valkor_fw_lacze;historia_do_wyslania;120'));
      expect(csv, contains('valkor_fw_lacze;rssi_tracker_teraz_dbm;niedostepne'));
      expect(csv, contains('valkor_fw_lacze;rssi_tracker_min_dbm;-95'));
      expect(csv, contains('valkor_fw_od_startu;historia_przywrocona_po_rozlaczeniu;52'));
    });
  });

  group('Panel testów terenowych', () {
    void phone(double lat, num s) => PhoneLocation.instance.onPosition(pos(lat, at(s)), now: at(s));

    test('zasięg Bluetooth: odległości przed utratą, po odzyskaniu, przerwy i czas bez pozycji osobno od utraconych pakietów', () {
      final ft = FieldTests.instance.start(FieldTestKind.bleRange, now: at(0), link: c);
      // Oddalanie: 1 m/s, pozycje co 1 s do 127 m.
      for (var s = 1; s <= 127; s++) {
        phone(north(0), s);
        dog(north(s.toDouble()), s);
      }
      // 50 s bez pozycji (poza zasięgiem), tracker nie wysyła – numeracja bez luk.
      for (var s = 128; s < 178; s++) {
        phone(north(0), s);
      }
      c.diag.addBleEvent(at(176), BleEvent.connected);
      for (var s = 178; s <= 190; s++) {
        phone(north(0), s);
        dog(north(111.0 - (s - 178)), s);
      }
      final r = ft.range(c, now: at(190.5));
      expect(r.maxWithTransmissionM, closeTo(127, 6));
      expect(r.lastBeforeLossM, closeTo(127, 6));
      expect(r.firstRecoveredM, closeTo(111, 6));
      expect(r.atReconnectM, closeTo(111, 6));
      expect(r.gaps.single.sec, closeTo(51, 0.5));
      expect(r.missingLiveSeconds, 50);
      final csv = ft.csv(c, now: at(190.5));
      expect(csv, contains('liczniki_testu;utracone_pakiety_protokolu;0'));
      expect(csv, contains('liczniki_testu;brakujace_pozycje_na_zywo_1hz;50'));
      expect(csv, contains('zasieg;rssi_tracker_sr_dbm;niedostepne'));
      expect(ft.extraRows(c, now: at(190.5)).map((e) => e.$1), contains('Pierwsza pozycja po utracie'));
    });

    test('dokładność: znacznik referencyjny zapisuje czas, wyświetlony stan i medianę z 10 s (bez korekty)', () {
      FieldTests.instance.start(FieldTestKind.distance, now: at(0), link: c);
      for (var s = 1; s <= 40; s++) {
        phone(north(0), s);
        dog(north(30), s);
      }
      final m = FieldTests.instance.mark(30, now: at(40.5), link: c)!;
      expect(m.refM, 30);
      expect(m.samples, greaterThanOrEqualTo(9));
      expect(m.medianRawM, closeTo(30, 0.5));
      final csv = FieldTests.instance.active!.csv(c, now: at(41));
      expect(csv, contains(ReferenceMark.csvHeader));
      expect(csv.split('\n').where((l) => l.startsWith('znacznik;2026-11-27T')), hasLength(1));
      expect(FieldTests.instance.mark(5, now: at(41), link: c), isNotNull);
      expect(FieldTests.instance.active!.marks, hasLength(2));
    });

    test('test dynamiczny: droga, prędkość, czas ruchu i postoju', () {
      final ft = FieldTests.instance.start(FieldTestKind.dynamic, now: at(0), link: c);
      for (var s = 1; s <= 60; s++) {
        phone(north(0), s);
        dog(north(s <= 30 ? s * 3.0 : 90), s);
      }
      final d = ft.dynamicStats(c, now: at(60.5));
      expect(d.maxFromPhoneM, greaterThan(80));
      expect(d.dogPathM, greaterThan(70));
      expect(d.phonePathM, lessThan(5));
    });
  });

  group('Niepewność na postoju (dryf w budynku większy niż deklarowana dokładność)', () {
    test('rozrzut na postoju podnosi niepewność, nigdy jej nie obniża; ruch czyści okno', () {
      final q = GnssQuality.valkor();
      GnssAssessment? a;
      // Deklarowane ±1,8 m (HDOP 0,6), a pozycja błądzi ±12 m na postoju.
      // 90 s: po oknie odzyskania sygnału (60 s) zostaje sam rozrzut.
      for (var i = 0; i < 90; i++) {
        final off = (i % 2 == 0 ? 12.0 : -12.0);
        a = q.add(LatLng(north(off), 20), at(i), accuracyM: 1.8, hdop: 0.6, sats: 20, speedMs: 0.1);
      }
      expect(a!.sigmaSource, 'rozrzut_postoju');
      expect(a.sigmaM, closeTo(12, 1));
      // Mały rozrzut: zostaje granica z HDOP.
      final q2 = GnssQuality.valkor();
      for (var i = 0; i < 90; i++) {
        a = q2.add(LatLng(north(i % 2 * 0.5), 20), at(i), accuracyM: 1.8, hdop: 0.6, sats: 20, speedMs: 0.1);
      }
      expect(a!.sigmaSource, 'hdop');
      expect(a.sigmaM, GnssQuality.floorHdopM);
      // Ruch: okno postoju wyczyszczone.
      a = q.add(LatLng(north(20), 20), at(91), accuracyM: 1.8, hdop: 0.6, sats: 20, speedMs: 2);
      expect(q.stillSpreadM, isNull);
    });
  });
}

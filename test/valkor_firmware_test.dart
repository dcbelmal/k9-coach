import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integracja z firmware Valkor Track 0.1.0 (kanał GPS bezpośrednio przez
/// Bluetooth). Pakiety budowane tak jak w firmware (docs/PROTOKOL.md).

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
    ..setUint8(14, 0)
    ..setUint8(15, mode);
  b.add(h.buffer.asUint8List());
  b.add(payload);
  final body = b.toBytes();
  final c = valkorCrc16(body);
  return Uint8List.fromList([...body, c & 0xFF, c >> 8]);
}

Uint8List position(double lat, DateTime fix, {bool historical = false, int age = 40, int? seq, int speedCmS = 30}) {
  final d = ByteData(36);
  final utc = fix.toUtc().millisecondsSinceEpoch;
  d
    ..setUint32(0, utc ~/ 1000, Endian.little)
    ..setUint16(4, utc % 1000, Endian.little)
    ..setInt32(6, (lat * 1e7).round(), Endian.little)
    ..setInt32(10, (20 * 1e7).round(), Endian.little)
    ..setInt32(14, 10000, Endian.little)
    ..setUint16(18, speedCmS, Endian.little)
    ..setUint16(20, 9000, Endian.little)
    ..setUint16(22, 210, Endian.little)
    ..setUint16(24, 70, Endian.little)
    ..setUint8(26, 11)
    ..setUint8(27, 1)
    ..setUint16(28, historical ? 0xFFFF : age, Endian.little)
    ..setUint16(30, 3950, Endian.little)
    ..setUint8(32, 81);
  final flags = ValkorFlags.fixValid | ValkorFlags.timeValid | ValkorFlags.accEstimated | (historical ? ValkorFlags.historical : 0);
  return frame(1, flags, d.buffer.asUint8List(), seq: seq);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final sent = <Uint8List>[];

  setUp(() async {
    _seq = 0;
    sent.clear();
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.valkorWriteOverride = (d) async => sent.add(d);
    c.writeOverride = (d) async {};
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
    await PhoneLocation.instance.resetForTest();
  });
  tearDown(() async {
    c.resetForTest();
    await PhoneLocation.instance.resetForTest();
  });

  test('pozycje co 1 s: każda przyjęta, pies na żywo, odstęp ~1 s, bez zapytań Meshtastic', () async {
    final got = <CollarFix>[];
    final sub = c.fixes.listen(got.add);
    for (var s = 1; s <= 30; s++) {
      c.handleValkor(position(north(s * 1.5), at(s - 0.05)), now: at(s));
    }
    expect(c.valkorActive, isTrue);
    expect(c.valkor!.firmware, '0.1.0');
    expect(c.valkor!.stats.live, 30);
    expect(c.valkor!.stats.lost, 0);
    expect(c.diag.accepted, 30);
    expect(c.diag.medianInterval, closeTo(1, 0.01));
    expect(c.status(now: at(30.5)), DogLink.live);
    expect(c.dog!.fix!.accuracyM, closeTo(2.1, 1e-6)); // HDOP 0,7 × 3 m – jak w firmware
    expect(c.dog!.battery, 81);
    expect(c.expectedIntervalSec, 1);
    c.markOpenedForTest(at(0));
    // Kanał Valkor dostarcza pakiety – bez zapytań Meshtastic.
    expect(c.positionRequestDue(at(30.5)), isNull);
    await pumpEventQueue();
    await sub.cancel();
    expect(got.where((f) => !f.historical).length, 30);
  });

  test('kopie pozycji z Meshtastic tego trackera są pomijane, gdy działa kanał Valkor', () {
    c.handleValkor(position(north(0), at(1)), now: at(1.05));
    c.handleEvents([MeshPositionEvent(1, MeshPosition(north(50), 20, time: at(2), hdop: 0.6), packetId: 9)], now: at(2.1));
    expect(c.valkor!.meshIgnored, 1);
    expect(c.dog!.fix!.lat, north(0));
  });

  test('pomiar historyczny: nigdy na żywo; starszy od bieżącej pozycji idzie do trasy (wstawiany w swoje miejsce)', () async {
    final got = <CollarFix>[];
    final sub = c.fixes.listen(got.add);
    c.sessionStart = at(-600);
    c.handleValkor(position(north(0), at(100)), now: at(100.05));
    c.handleValkor(position(north(30), at(40), historical: true), now: at(100.5));
    expect(c.valkor!.stats.historical, 1);
    expect(c.valkor!.historyBeforeLive, 1);
    expect(c.valkor!.historyRecovered, 1);
    expect(c.dog!.lastHistorical!.historical, isTrue);
    expect(c.dog!.fix!.lat, north(0)); // pozycja na żywo bez zmian
    await pumpEventQueue();
    // 0.27.1: historia trafia do trasy (TrackRecorder wstawia ją według czasu pomiaru).
    expect(got.where((f) => f.historical), hasLength(1));
    expect(got.where((f) => f.historical).single.source, FixSource.valkorHistory);
    expect(c.diag.historical, 1);
    await sub.cancel();
    // Historia sprzed pierwszej pozycji na żywo (np. zaraz po połączeniu) – do trasy jako historyczna.
    c.resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    c.sessionStart = at(-600);
    final sub2 = c.fixes.listen(got.add);
    c.handleValkor(position(north(30), at(40), historical: true, seq: 1), now: at(100.5));
    await pumpEventQueue();
    expect(got.where((f) => f.historical).length, 2);
    expect(c.status(now: at(100.6)), isNot(DogLink.live));
    await sub2.cancel();
  });

  test('utracone i powtórzone pakiety, uszkodzona ramka', () {
    c.handleValkor(position(north(0), at(1), seq: 1), now: at(1));
    c.handleValkor(position(north(1), at(2), seq: 2), now: at(2));
    c.handleValkor(position(north(1), at(2), seq: 2), now: at(2.1)); // duplikat
    c.handleValkor(position(north(2), at(5), seq: 5), now: at(5));
    final bad = position(north(3), at(6), seq: 6)..[20] ^= 1;
    c.handleValkor(bad, now: at(6));
    expect(c.valkor!.stats.lost, 2);
    expect(c.valkor!.stats.duplicates, 1);
    expect(c.valkor!.stats.badFrames, 1);
    expect(c.diag.accepted, 3);
  });

  test('zmiana trybu w aplikacji wysyła tryb do firmware', () async {
    c.handleValkor(position(north(0), at(1)), now: at(1));
    await c.setMode(TrackMode.saver);
    final cmd = sent.last;
    expect(cmd[2], ValkorCmd.setMode);
    expect(cmd[4], ValkorMode.eco.code);
    await c.setMode(TrackMode.sport);
    expect(sent.last[4], ValkorMode.sport.code);
  });

  test('status i diagnostyka z trackera trafiają do CSV', () {
    final st = ByteData(16)
      ..setUint32(0, 3500, Endian.little)
      ..setUint8(4, 3)
      ..setUint16(8, 3900, Endian.little)
      ..setUint8(10, 70);
    c.handleValkor(frame(2, 0, st.buffer.asUint8List()), now: at(1));
    final dg = ByteData(44)
      ..setUint32(0, 600, Endian.little)
      ..setUint16(12, 1002, Endian.little)
      ..setUint16(14, 1180, Endian.little)
      ..setInt8(36, -68);
    c.handleValkor(frame(4, 0, dg.buffer.asUint8List()), now: at(2));
    expect(c.valkor!.status!.gnss, ValkorGnss.lost);
    expect(c.valkor!.gnssIntervalSec, closeTo(1.002, 1e-9));
    final csv = c.diag.csv(extra: c.valkor!.csvLines());
    expect(csv, contains('valkor_fw_od_startu;gnss_odstep_sr_ms;1002'));
    expect(csv, contains('valkor_fw_od_startu;gnss_odstep_max_ms;1180'));
    expect(csv, contains('valkor;firmware;0.1.0'));
    expect(c.valkor!.rows().any((r) => r.$2.contains('1,0 s')), isTrue);
  });

  test('bez usługi Valkor wszystko jak dotąd (Meshtastic)', () {
    expect(c.valkor, isNull);
    expect(c.valkorActive, isFalse);
    c.handleEvents([MeshPositionEvent(1, MeshPosition(north(0), 20, time: at(2), hdop: 0.6), packetId: 9)], now: at(2.1));
    expect(c.dog!.fix, isNotNull);
  });
}

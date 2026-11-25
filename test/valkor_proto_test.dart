import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/valkor_proto.dart';

List<int> hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

// Wektory z valkor-track-firmware/tests/vectors/protocol_v1.txt (koder C++ firmware 0.1.0).
const vPosition =
    '56010109d4c3b2a1050000000001000000812469fa008768111f866a930c102700000b0228230e015a000c011f006e0f4d000000dcda';

const vStatus = '56010209d4c3b2a1050000000001000068100000030000000000ff000000000001ef';
const vInfo = '56010309d4c3b2a1050000000001000001000000e8030000322e372e31352e3536376238656100001696';
const vDiag = '56010409d4c3b2a10500000000010000630000000000000000000000e80300000000000000000000000000000000000000000000b900000000000000c19f';
const vAck = '56010509d4c3b2a10500000000010000020000006f12';

void main() {
  test('status, info, diag, ack z firmware', () {
    final s = decodeValkor(hex(vStatus)) as ValkorStatus;
    expect(s.lastFixAgeMs, 4200);
    expect(s.gnss, ValkorGnss.lost);
    final i = decodeValkor(hex(vInfo)) as ValkorInfo;
    expect(i.upstream, '2.7.15.567b8ea');
    expect(i.hwName, 'SenseCAP T1000-E');
    expect(i.gnssPeriodMs, 1000);
    final d = decodeValkor(hex(vDiag)) as ValkorDiag;
    expect(d.uptimeS, 99);
    expect(d.gnssIntervalAvgMs, 1000);
    expect(d.rssi, -71);
    final a = decodeValkor(hex(vAck)) as ValkorAck;
    expect(a.command, ValkorCmd.setMode);
    expect(a.ok, isTrue);
  });

  test('crc16 CCITT-FALSE', () {
    expect(valkorCrc16('123456789'.codeUnits), 0x29B1);
  });

  test('pozycja z firmware', () {
    final p = decodeValkor(hex(vPosition)) as ValkorPosition;
    expect(p.h.type, ValkorType.position);
    expect(p.h.deviceId, 0xA1B2C3D4);
    expect(p.h.seq, 5);
    expect(p.h.firmware, '0.1.0');
    expect(p.h.historical, isFalse);
    expect(p.lat, closeTo(52.1234567, 1e-9));
    expect(p.lng, closeTo(21.0987654, 1e-9));
    expect(p.fixTime, DateTime.fromMillisecondsSinceEpoch(1764000000 * 1000 + 250, isUtc: true));
    expect(p.speedMs, closeTo(5.23, 1e-9));
    expect(p.courseDeg, closeTo(90, 1e-9));
    expect(p.accuracyM, closeTo(2.7, 1e-9));
    expect(p.hdop, closeTo(0.9, 1e-9));
    expect(p.sats, 12);
    expect(p.ageMs, 31);
    expect(p.batteryPct, 77);
    expect(p.altM, closeTo(100, 1e-9));
  });

  test('uszkodzona ramka odrzucona', () {
    final b = hex(vPosition);
    b[20] ^= 1;
    expect(decodeValkor(b), isNull);
    expect(decodeValkor(hex(vPosition).sublist(0, 30)), isNull);
  });

  test('komenda SET_MODE', () {
    final c = valkorCommand(ValkorCmd.setMode, token: 9, arg: 2);
    expect(c.sublist(0, 5), [0x56, 1, 2, 9, 2]);
    expect(valkorCrc16(c, c.length - 2), c[c.length - 2] | (c[c.length - 1] << 8));
  });

  test('liczniki: utracone, duplikaty, restart', () {
    final s = ValkorLinkStats();
    expect(s.seq(1), isTrue);
    expect(s.seq(2), isTrue);
    expect(s.seq(2), isFalse);
    expect(s.seq(5), isTrue);
    expect(s.lost, 2);
    expect(s.duplicates, 1);
    s.seq(1);
    expect(s.restarts, 1);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/gps_drafts.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/screens/collar_screen.dart';
import 'package:k9_coach/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FromRadio { packet { from, rx_rssi, decoded { portnum, payload } } }.
List<int> packet(int from, int port, List<int> payload, {int rssi = -90}) {
  final data = PbWriter()
    ..varint(1, port)
    ..bytes(2, payload);
  final pk = PbWriter()
    ..fixed32(1, from)
    ..fixed32(2, 0xffffffff)
    ..bytes(4, data.toBytes())
    ..varint(12, rssi);
  return (PbWriter()
        ..varint(1, 7)
        ..bytes(2, pk.toBytes()))
      .toBytes();
}

List<int> position(double lat, double lng, {int? time, int? speed}) {
  final w = PbWriter()
    ..fixed32(1, (lat * 1e7).round() & 0xffffffff)
    ..fixed32(2, (lng * 1e7).round() & 0xffffffff)
    ..varint(3, 120);
  if (time != null) w.fixed32(4, time);
  if (speed != null) w.varint(15, speed);
  return w.toBytes();
}

List<int> nodeInfo(int num, String longName, String shortName, int hw, {int? battery}) {
  final user = PbWriter()
    ..bytes(1, utf8.encode(meshNodeId(num)))
    ..bytes(2, utf8.encode(longName))
    ..bytes(3, utf8.encode(shortName))
    ..varint(5, hw);
  final ni = PbWriter()
    ..varint(1, num)
    ..bytes(2, user.toBytes());
  if (battery != null) ni.bytes(6, (PbWriter()..varint(1, battery)).toBytes());
  return (PbWriter()..bytes(4, ni.toBytes())).toBytes();
}

List<int> myInfo(int num) => (PbWriter()..bytes(3, (PbWriter()..varint(1, num)).toBytes())).toBytes();

void main() {
  group('Protokół Meshtastic', () {
    test('pozycja z pakietu POSITION_APP (także ujemne współrzędne)', () {
      final ev = decodeFromRadio(packet(0xa1b2c3d4, MeshPort.position, position(52.2297, -21.0122, time: 1700000000, speed: 4)));
      expect(ev, hasLength(1));
      final p = ev.single as MeshPositionEvent;
      expect(p.node, 0xa1b2c3d4);
      expect(p.position.lat, closeTo(52.2297, 1e-7));
      expect(p.position.lng, closeTo(-21.0122, 1e-7));
      expect(p.position.altitude, 120);
      expect(p.position.speedMs, 4);
      expect(p.position.time!.toUtc(), DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(p.rssi, -90);
    });

    test('pozycja 0,0 (brak fixu) jest pomijana', () {
      expect(decodeFromRadio(packet(5, MeshPort.position, position(0, 0))), isEmpty);
    });

    test('informacje o urządzeniu i numer własny', () {
      final ni = decodeFromRadio(nodeInfo(77, 'Pies Gamora', 'GAM', hwT1000E, battery: 83)).single as MeshNodeInfo;
      expect(ni.node, 77);
      expect(ni.longName, 'Pies Gamora');
      expect(ni.shortName, 'GAM');
      expect(ni.hwModel, hwT1000E);
      expect(ni.battery, 83);
      expect((decodeFromRadio(myInfo(0xdeadbeef)).single as MeshMyInfo).myNode, 0xdeadbeef);
    });

    test('bateria z telemetrii', () {
      final dm = (PbWriter()..varint(1, 64)).toBytes();
      final tel = (PbWriter()
            ..fixed32(1, 1700000000)
            ..bytes(2, dm))
          .toBytes();
      final b = decodeFromRadio(packet(9, MeshPort.telemetry, tel)).single as MeshBattery;
      expect(b.level, 64);
    });

    test('nieznane pola i porty nie psują odczytu', () {
      final w = PbWriter()
        ..varint(99, 5)
        ..bytes(98, [1, 2, 3])
        ..fixed32(97, 1);
      expect(decodeFromRadio(w.toBytes()), isEmpty);
      expect(decodeFromRadio(packet(1, 1, utf8.encode('cześć'))), isEmpty);
      expect(decodeFromRadio(const []), isEmpty);
    });

    test('prośba o pozycję ma poprawną budowę', () {
      final f = PbFields.parse(encodePositionRequest(0x1234abcd, id: 42));
      final pk = f.message(1)!;
      expect(pk.integer(2), 0x1234abcd);
      expect(pk.integer(6), 42);
      final data = pk.message(4)!;
      expect(data.integer(1), MeshPort.position);
      expect(data.integer(3), 1);
      expect(PbFields.parse(encodeWantConfig(321)).integer(3), 321);
    });
  });

  group('Obroża – wybór psa i pozycje', () {
    final c = CollarLink.instance;
    setUp(c.resetForTest);

    test('jedna obroża: pies to urządzenie połączone z telefonem', () async {
      c.handleEvents([...decodeFromRadio(myInfo(10)), ...decodeFromRadio(nodeInfo(10, 'Pies', 'PS', hwT1000E))]);
      expect(c.dogNode, 10);
      expect(c.direct, isTrue);
      final got = <CollarFix>[];
      final sub = c.fixes.listen(got.add);
      c.handleEvents(decodeFromRadio(packet(10, MeshPort.position, position(50.1, 19.9))));
      await Future<void>.delayed(Duration.zero);
      expect(got.single.lat, closeTo(50.1, 1e-6));
      expect(c.dogWithFix, isNotNull);
      await sub.cancel();
    });

    test('dwa urządzenia: pies to obroża T1000-E w sieci, nie odbiornik w kieszeni', () async {
      c.handleEvents([
        ...decodeFromRadio(myInfo(1)),
        ...decodeFromRadio(nodeInfo(1, 'Kieszeń', 'KZ', 43)),
        ...decodeFromRadio(nodeInfo(2, 'Pies', 'PS', hwT1000E)),
      ]);
      expect(c.dogNode, 2);
      expect(c.direct, isFalse);
      final got = <CollarFix>[];
      final sub = c.fixes.listen(got.add);
      c.handleEvents(decodeFromRadio(packet(1, MeshPort.position, position(50, 20))));
      c.handleEvents(decodeFromRadio(packet(2, MeshPort.position, position(50.001, 20.001))));
      await Future<void>.delayed(Duration.zero);
      expect(got.map((f) => f.node), [2]);
      // Ręczny wybór ma pierwszeństwo.
      c.dogNodeChoice = 1;
      expect(c.dogNode, 1);
      await sub.cancel();
    });

    test('pozycja z bazy urządzenia (stara) nie trafia do trasy', () async {
      final got = <CollarFix>[];
      final sub = c.fixes.listen(got.add);
      c.handleEvents([const MeshMyInfo(3), MeshNodeInfo(3, position: const MeshPosition(50, 20))]);
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty);
      expect(c.dogWithFix, isNull);
      await sub.cancel();
    });
  });

  group('Trasa psa w zapisie treningu', () {
    test('Track zapisuje i odczytuje trasę psa; stare pliki bez psa działają', () {
      final t = Track([
        [const TrackPoint(50, 20, 0), const TrackPoint(50.001, 20, 10)]
      ], [], [
        const TrackPoint(50, 20, 0),
        const TrackPoint(50.002, 20, 15, 3.2)
      ]);
      final back = Track.decode(t.encode());
      expect(back.hasDog, isTrue);
      expect(back.dog.last.speed, 3.2);
      expect(back.dogMeters, closeTo(222, 2));
      final old = Track.decode(jsonEncode({
        'v': 1,
        's': [
          [
            [50, 20, 0],
            [50.001, 20, 5]
          ]
        ],
      }));
      expect(old.dog, isEmpty);
      expect(old.hasDog, isFalse);
    });

    test('szkic treningu przechowuje trasę psa (odzyskanie po zamknięciu aplikacji)', () {
      final d = GpsDraft(
        sessionId: 's1',
        dogId: 'd1',
        discipline: Discipline.canicross,
        startedAt: DateTime(2026, 11, 23, 10),
        dog: [const TrackPoint(50, 20, 1), const TrackPoint(50.001, 20, 20)],
      );
      final back = GpsDraft.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.dog, hasLength(2));
      expect(back.hasRoute, isTrue);
      expect(back.track.hasDog, isTrue);
    });
  });

  group('Ekran obroży', () {
    final c = CollarLink.instance;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      c.resetForTest();
    });
    Widget app() => MaterialApp(theme: K9.theme(), home: const CollarScreen());

    testWidgets('bez obroży: wyszukiwanie i instrukcja', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('Szukaj obroży'), findsOneWidget);
      expect(find.text('Jak przygotować obrożę'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('połączona z dwoma urządzeniami: wybór psa zmienia źródło pozycji', (tester) async {
      c.deviceId = 'aa:bb';
      c.deviceName = 'Kieszeń';
      c.state = CollarState.connected;
      c.handleEvents([
        const MeshMyInfo(1),
        const MeshNodeInfo(1, longName: 'Kieszeń', hwModel: 43),
        const MeshNodeInfo(2, longName: 'Pies Gamora', hwModel: hwT1000E, battery: 77),
      ]);
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('Które urządzenie jest na psie?'), findsOneWidget);
      expect(find.text('Pies Gamora'), findsOneWidget);
      expect(c.dogNode, 2);
      await tester.tap(find.textContaining('To połączone z telefonem'));
      await tester.pump();
      expect(c.dogNode, 1);
      await tester.pumpWidget(const SizedBox());
      c.state = CollarState.off;
    });
  });
}

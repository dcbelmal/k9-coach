import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/screens/valkor_track_screen.dart';
import 'package:k9_coach/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final c = CollarLink.instance;
  var active = 'main';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c.resetForTest();
    active = 'main';
    CollarLink.activeDog = () => active;
  });

  group('Przypisanie trackera do psa', () {
    test('każdy pies ma swój tracker; nieprzypisany wybierany automatycznie', () async {
      c.handleEvents([
        const MeshMyInfo(1),
        MeshNodeInfo(2, hwModel: hwT1000E),
        MeshNodeInfo(3, hwModel: hwT1000E),
      ]);
      // Dwa trackery w sieci: bez przypisania nie zgadujemy – telefon.
      expect(c.dogNode, 1);
      await c.assign(2, 'main');
      await c.assign(3, 'reks');
      expect(c.dogNode, 2);
      active = 'reks';
      expect(c.dogNode, 3);
      expect(c.nodeForDog('main'), 2);
      expect(c.dogFor(3), 'reks');
      // Nowy pies bez trackera nie dostaje cudzego.
      active = 'luna';
      expect(c.dogNode, 1);
    });

    test('jeden tracker na psa – ponowne przypisanie przenosi', () async {
      await c.assign(2, 'main');
      await c.assign(3, 'main');
      expect(c.dogFor(2), isNull);
      expect(c.nodeForDog('main'), 3);
      await c.assign(3, null);
      expect(c.assigned, isEmpty);
    });

    test('wybór na ekranie przypisuje tracker do aktualnego psa', () async {
      await c.chooseDog(5);
      expect(c.dogFor(5), 'main');
    });

    test('przypisania zapisują się i wczytują; stary zapis bez nich działa', () async {
      c.deviceId = 'ble-1';
      await c.assign(7, 'reks');
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString('valkor_collar_v1')!) as Map<String, dynamic>;
      expect(raw['assign'], {'7': 'reks'});
      c.resetForTest(loaded: false);
      await c.load();
      expect(c.dogFor(7), 'reks');
      expect(c.deviceId, 'ble-1');

      SharedPreferences.setMockInitialValues({
        'valkor_collar_v1': jsonEncode({'id': 'x', 'name': 'T1000-E', 'dog': 9}),
      });
      c.resetForTest(loaded: false);
      await c.load();
      expect(c.assigned, isEmpty);
      expect(c.dogNode, 9);
    });
  });

  group('Prędkość i kierunek psa', () {
    test('z dwóch pomiarów z ruchem', () {
      final t = DateTime.now().subtract(const Duration(seconds: 30));
      c.handleEvents([
        const MeshMyInfo(4),
        MeshPositionEvent(4, MeshPosition(50, 20, time: t)),
        MeshPositionEvent(4, MeshPosition(50.0009, 20, time: t.add(const Duration(seconds: 20)))), // ~100 m na północ
      ]);
      final n = c.dog!;
      expect(n.speedMs, closeTo(5, 0.1));
      expect(n.courseDeg, closeTo(0, 1));
    });

    test('prędkość z trackera ma pierwszeństwo', () {
      c.handleEvents([
        const MeshMyInfo(4),
        MeshPositionEvent(4, MeshPosition(50, 20, time: DateTime.now(), speedMs: 3)),
      ]);
      expect(c.dog!.speedMs, 3);
      expect(c.dog!.courseDeg, isNull);
    });

    test('strony świata', () {
      expect(compassLabel(0), 'PN');
      expect(compassLabel(44), 'PN-WSCH');
      expect(compassLabel(180), 'PD');
      expect(compassLabel(350), 'PN');
      expect(compassLabel(-90), 'ZACH');
    });
  });

  group('Ekran Valkor Track', () {
    setUp(() {
      GpsServices.reset();
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.denied;
      GpsServices.tiles = () => const SizedBox.shrink();
      GpsServices.topoTiles = () => const SizedBox.shrink();
    });
    tearDown(GpsServices.reset);

    testWidgets('bez zgody na mapę: brak kafli, stan psa i ostatnia znana pozycja', (tester) async {
      OnlineConsent.instance.map = false;
      c.deviceId = 'x';
      c.state = CollarState.connected;
      final old = DateTime.now().subtract(const Duration(minutes: 10));
      c.handleEvents([
        const MeshMyInfo(4),
        MeshPositionEvent(4, MeshPosition(50, 20, time: old.add(const Duration(minutes: 9, seconds: 50)))),
      ]);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const ValkorTrackScreen()));
      await tester.pump();
      expect(find.text('Valkor Track'), findsOneWidget);
      expect(find.text('Włącz mapę'), findsOneWidget);
      expect(find.text('GPS psa'), findsOneWidget);
      expect(find.textContaining('na żywo'), findsOneWidget);
      // Pomiar postarzały: już nie „na żywo”.
      c.nodes[4]!.fix = CollarFix(4, 50, 20, old);
      c.notifyListeners();
      await tester.pump();
      expect(find.textContaining('ostatnia znana pozycja'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mieści się na wąskim telefonie', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      OnlineConsent.instance.map = false;
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([
        const MeshMyInfo(4),
        MeshNodeInfo(4, battery: 87),
        MeshPositionEvent(4, MeshPosition(50, 20, time: DateTime.now())),
      ]);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const ValkorTrackScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('87%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bez trackera: przycisk dodania', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const ValkorTrackScreen()));
      await tester.pump();
      expect(find.text('Dodaj tracker'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

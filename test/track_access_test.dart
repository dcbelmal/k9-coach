import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/screens/shell.dart';
import 'package:k9_coach/screens/valkor_track_screen.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_prefs.dart';

void main() {
  final c = CollarLink.instance;

  group('Ostatnia znana pozycja i stan dla wielu psów', () {
    var active = 'main';
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      c.resetForTest();
      active = 'main';
      CollarLink.activeDog = () => active;
    });

    test('pozycja psa zapamiętana i odczytana po ponownym uruchomieniu', () async {
      c.deviceId = 'ble';
      final t = DateTime.now().subtract(const Duration(seconds: 5));
      c.handleEvents([
        const MeshMyInfo(4),
        MeshNodeInfo(4, battery: 64),
        MeshPositionEvent(4, MeshPosition(50.1, 19.9, time: t)),
      ]);
      expect(c.lastKnown('main')!.lat, closeTo(50.1, 1e-6));
      await Future<void>.delayed(Duration.zero);
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString('valkor_collar_v1')!) as Map<String, dynamic>;
      expect((raw['last'] as Map)['main'], isNotNull);

      c.resetForTest(loaded: false);
      await c.load();
      final l = c.lastKnown('main')!;
      expect(l.lat, closeTo(50.1, 1e-6));
      expect(l.battery, 64);
      expect(l.at.difference(t).inSeconds.abs(), lessThanOrEqualTo(1));
      // Bez połączenia: stan „brak Bluetooth”, ale pozycja nadal znana.
      expect(c.status(), DogLink.bluetoothOff);
    });

    test('uszkodzony zapis pozycji jest pomijany, reszta ustawień działa', () async {
      SharedPreferences.setMockInitialValues({
        'valkor_collar_v1': jsonEncode({
          'id': 'ble',
          'last': {
            'main': {'lat': 'x'},
            'reks': {'lat': 200, 'lng': 10, 'at': '2026-01-01T00:00:00'},
            'luna': {'lat': 50, 'lng': 20, 'at': '2026-01-01T00:00:00'},
          },
        }),
      });
      c.resetForTest(loaded: false);
      await c.load();
      expect(c.deviceId, 'ble');
      expect(c.lastSeen.keys, ['luna']);
    });

    test('pies bez przypisanego trackera nie dostaje cudzego', () async {
      c.deviceId = 'ble';
      c.state = CollarState.connected;
      c.handleEvents([const MeshMyInfo(4), MeshPositionEvent(4, MeshPosition(50, 20, time: DateTime.now()))]);
      expect(c.status(dogId: 'main'), DogLink.live);
      expect(c.status(dogId: 'reks'), DogLink.none);
      expect(c.lastKnown('reks'), isNull);
      await c.assign(4, 'reks');
      expect(c.status(dogId: 'reks'), DogLink.live);
    });

    test('starsza zapamiętana pozycja nie nadpisuje nowszej', () {
      final now = DateTime.now();
      c.lastSeen['main'] = LastSeen(51, 21, now);
      c.handleEvents([
        const MeshMyInfo(4),
        MeshPositionEvent(4, MeshPosition(50, 20, time: now.subtract(const Duration(seconds: 50)))),
      ]);
      expect(c.lastKnown('main')!.lat, 51);
    });
  });

  group('Valkor Track w nawigacji', () {
    late Directory dir;
    setUpAll(() async => initializeDateFormatting());
    setUp(() async {
      installFakeDisk();
      dir = await useTempFiles();
      await restartApp();
      c.resetForTest();
      CollarLink.activeDog = () => 'main';
      await AppStore.instance.saveDog(Dog(name: 'Belg', weightKg: 30));
      goToTab(0);
      GpsServices.reset();
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.denied;
      GpsServices.tiles = () => const SizedBox.shrink();
      OnlineConsent.instance.map = false;
    });
    tearDown(() {
      GpsServices.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    testWidgets('zakładka Track i karta na Start otwierają lokalizację bez treningu', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const Shell()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('home-track')), findsOneWidget);
      expect(find.text('Track'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('home-track')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ValkorTrackScreen), findsOneWidget);
      expect(find.text('Dodaj tracker'), findsOneWidget);
      expect(tester.takeException(), isNull);

      goToTab(1);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Track'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ValkorTrackScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/screens/dog_radar.dart';
import 'package:k9_coach/screens/valkor_track_screen.dart';
import 'package:k9_coach/theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final t0 = DateTime.utc(2026, 11, 23, 12);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const home = LatLng(50, 20);

/// Pomiar psa [northM] metrów na północ od przewodnika.
CollarFix fx(double northM, num s, {double? acc}) => CollarFix(1, 50 + northM / 111195, 20, at(s), accuracyM: acc);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wirtualna smycz', () {
    late AlertEngine e;
    setUp(() => e = AlertEngine(AlertSettings(enabled: true, leashM: 100, lowBattery: null)));

    // Odległość z pozycji telefonu z tej samej chwili co pomiar psa
    // (niepewność ~10 m jak przy domyślnym błędzie GPS).
    DogDistance dist(double m, {double unc = 10}) => DogDistance(matchedM: m, matchedUncertaintyM: unc, ageSec: 0, lagSec: 0);
    List<AlertKind> step(double m, num s, {DogLink link = DogLink.live, double? acc}) => [
          for (final a in e.evaluate(AlertInput(
              now: at(s), link: link, fix: fx(m, s, acc: acc), handler: home, distance: dist(m, unc: (acc ?? 10).clamp(5, 50).toDouble()))))
            a.kind
        ];

    test('alarm dopiero po 2 pomiarach poza smyczą', () {
      expect(step(50, 0), isEmpty);
      expect(step(150, 5), isEmpty);
      expect(step(160, 10), [AlertKind.leash]);
    });

    test('zapas na błąd GPS: tuż za granicą nie ma alarmu', () {
      expect(step(105, 0), isEmpty);
      expect(step(108, 5), isEmpty);
    });

    test('jeden skok poza granicę nie robi alarmu', () {
      expect(step(200, 0), isEmpty);
      expect(step(50, 5), isEmpty);
      expect(step(200, 10), isEmpty);
    });

    test('bez powtórek; po powrocie (histereza) uzbraja się ponownie', () {
      step(150, 0);
      expect(step(150, 5), [AlertKind.leash]);
      expect(step(170, 10), isEmpty);
      expect(step(90, 15), isEmpty); // 90 m: jeszcze nie „wyraźnie bliżej”
      expect(step(60, 20), [AlertKind.backInRange]);
      step(150, 100);
      expect(step(150, 105), [AlertKind.leash]);
    });

    test('nieaktualna pozycja nie uruchamia smyczy', () {
      expect(step(300, 0, link: DogLink.stale), isEmpty);
      expect(step(300, 5, link: DogLink.stale), isEmpty);
    });

    test('ten sam pomiar drugi raz nie liczy się jako kolejny', () {
      e.evaluate(AlertInput(now: at(0), link: DogLink.live, fix: fx(150, 0), handler: home, distance: dist(150)));
      final out = e.evaluate(AlertInput(now: at(3), link: DogLink.live, fix: fx(150, 0), handler: home, distance: dist(150)));
      expect(out, isEmpty);
    });

    test('stara pozycja telefonu (bez dopasowania w czasie) nie uruchamia smyczy', () {
      // Jest tylko „jakaś” pozycja przewodnika – bez odległości z tej samej chwili.
      e.evaluate(AlertInput(now: at(0), link: DogLink.live, fix: fx(500, 0), handler: home));
      expect(e.evaluate(AlertInput(now: at(5), link: DogLink.live, fix: fx(500, 5), handler: home)), isEmpty);
    });

    test('pomiar zaległy (historyczny) nie uruchamia smyczy', () {
      CollarFix old(num s) => CollarFix(1, 50 + 500 / 111195, 20, at(s), historical: true);
      e.evaluate(AlertInput(now: at(0), link: DogLink.live, fix: old(0), handler: home, distance: dist(500)));
      expect(e.evaluate(AlertInput(now: at(5), link: DogLink.live, fix: old(5), handler: home, distance: dist(500))), isEmpty);
    });

    test('bez pozycji przewodnika smycz nie działa', () {
      e.evaluate(AlertInput(now: at(0), link: DogLink.live, fix: fx(500, 0)));
      expect(e.evaluate(AlertInput(now: at(5), link: DogLink.live, fix: fx(500, 5))), isEmpty);
    });

    test('wyłączone alarmy milczą', () {
      e.settings.enabled = false;
      step(500, 0);
      expect(step(500, 5), isEmpty);
    });
  });

  group('Strefy, utrata psa, bateria', () {
    test('wyjście poza strefę po 2 pomiarach, ponowne uzbrojenie w środku', () {
      final e = AlertEngine(AlertSettings(enabled: true, leashM: null, lowBattery: null, zones: [const SafeZone('Dom', 50, 20, 100)]));
      List<AlertKind> step(double m, num s) =>
          [for (final a in e.evaluate(AlertInput(now: at(s), link: DogLink.live, fix: fx(m, s)))) a.kind];
      expect(step(50, 0), isEmpty);
      expect(step(130, 5), isEmpty);
      expect(step(140, 10), [AlertKind.zone]);
      expect(step(20, 15), isEmpty);
      step(140, 100);
      expect(step(140, 105), [AlertKind.zone]);
    });

    test('utrata sygnału po ustalonym czasie i „znów widzę psa”', () {
      final e = AlertEngine(AlertSettings(enabled: true, leashM: null, lowBattery: null, lostSec: 60));
      expect(e.evaluate(AlertInput(now: at(0), link: DogLink.live, fix: fx(0, 0))), isEmpty);
      expect(e.evaluate(AlertInput(now: at(50), link: DogLink.stale)), isEmpty);
      final lost = e.evaluate(AlertInput(now: at(61), link: DogLink.connecting));
      expect(lost.single.kind, AlertKind.lost);
      expect(lost.single.text, contains('Bluetooth'));
      expect(e.evaluate(AlertInput(now: at(90), link: DogLink.connecting)), isEmpty);
      expect(e.evaluate(AlertInput(now: at(95), link: DogLink.live, fix: fx(0, 95))).single.kind, AlertKind.found);
    });

    test('bez wcześniejszej pozycji na żywo nie ma alarmu utraty', () {
      final e = AlertEngine(AlertSettings(enabled: true, lostSec: 60));
      expect(e.evaluate(AlertInput(now: at(500), link: DogLink.waitingGps)), isEmpty);
    });

    test('słaba bateria raz; ponownie dopiero po naładowaniu', () {
      final e = AlertEngine(AlertSettings(enabled: true, leashM: null, lowBattery: 20));
      List<AlertKind> b(int v, num s) => [for (final a in e.evaluate(AlertInput(now: at(s), link: DogLink.live, battery: v))) a.kind];
      expect(b(25, 0), isEmpty);
      expect(b(19, 100), [AlertKind.lowBattery]);
      expect(b(18, 200), isEmpty);
      expect(b(22, 300), isEmpty);
      expect(b(30, 400), isEmpty);
      expect(b(15, 500), [AlertKind.lowBattery]);
      expect(b(101, 600), isEmpty); // zasilanie z kabla
    });

    test('ustawienia zapisują się i wczytują (także stare/niepełne)', () {
      final s = AlertSettings(enabled: true, leashM: null, zones: [const SafeZone('A', 50, 20, 80)], lostSec: 180, voice: false);
      final back = AlertSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.enabled, isTrue);
      expect(back.leashM, isNull);
      expect(back.zones.single.radiusM, 80);
      expect(back.lostSec, 180);
      expect(back.voice, isFalse);
      final empty = AlertSettings.fromJson({'zones': [{'a': 'x'}]});
      expect(empty.leashM, 100);
      expect(empty.zones, isEmpty);
      expect(empty.enabled, isFalse);
    });
  });

  group('Tryby pracy', () {
    final c = CollarLink.instance;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      c.resetForTest();
    });

    test('poszukiwanie wraca do poprzedniego trybu i nie przetrwa restartu', () async {
      c.deviceId = 'x';
      await c.setMode(TrackMode.sport);
      await c.setMode(TrackMode.search);
      c.resetForTest(loaded: false);
      await c.load();
      expect(c.mode, TrackMode.sport);
      await c.setMode(TrackMode.search);
      await c.endSearch();
      expect(c.mode, TrackMode.sport);
    });

    test('rzeczywisty odstęp dłuższy niż zakłada tryb', () async {
      await c.setMode(TrackMode.sport);
      for (final s in [8.0, 9.0, 8.0]) {
        c.diag.addInterval(s);
      }
      expect(c.slowerThanMode, isTrue);
      await c.setMode(TrackMode.walk);
      expect(c.slowerThanMode, isFalse);
    });

    test('zakres radaru', () {
      expect(radarRange(10), 25);
      expect(radarRange(80), 100);
      expect(radarRange(95), 200);
      expect(radarRange(1500), 2000);
    });
  });

  group('Ekran: poszukiwanie i alarmy', () {
    final c = CollarLink.instance;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      c.resetForTest();
      DogAlerts.instance.resetForTest();
      GpsServices.reset();
      GpsServices.serviceEnabled = () async => true;
      GpsServices.checkPermission = () async => LocationPermission.denied;
      GpsServices.requestPermission = () async => LocationPermission.denied;
      GpsServices.tiles = () => const SizedBox.shrink();
      OnlineConsent.instance.map = false;
    });
    tearDown(GpsServices.reset);

    testWidgets('„Szukaj psa” włącza radar i tryb poszukiwania, „Mapa” wraca', (tester) async {
      c.deviceId = 'x';
      c.state = CollarState.connected;
      c.handleEvents([const MeshMyInfo(4), MeshPositionEvent(4, MeshPosition(50, 20, time: DateTime.now()))]);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const ValkorTrackScreen()));
      await tester.pump();
      await tester.tap(find.text('Szukaj psa'));
      await tester.pump();
      await tester.pump();
      expect(c.mode, TrackMode.search);
      expect(find.byType(DogRadar), findsOneWidget);
      // Bez lokalizacji telefonu nie ma liczby ze starych danych – wprost to mówimy.
      expect(find.text('Oczekiwanie na lokalizację telefonu'), findsWidgets);
      await tester.tap(find.text('Mapa'));
      await tester.pump();
      await tester.pump();
      expect(c.mode, TrackMode.walk);
      expect(find.byType(DogRadar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ustawienia śledzenia: tryb i alarmy', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.deviceId = 'x';
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const ValkorTrackScreen()));
      await tester.pump();
      await tester.tap(find.byTooltip('Ustawienia śledzenia'));
      await tester.pumpAndSettle();
      expect(find.text('Tryb pracy'), findsOneWidget);
      await tester.tap(find.text('Sportowy'));
      await tester.pump();
      expect(c.mode, TrackMode.sport);
      await tester.tap(find.text('Alarmy włączone'));
      await tester.pump();
      expect(DogAlerts.instance.settings.enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
      await DogAlerts.instance.save(AlertSettings());
    });

    test('alarm z silnika trafia do historii (bez dźwięku w testach)', () async {
      final got = <DogAlert>[];
      final a = DogAlerts.instance..onAlert = got.add;
      await a.save(AlertSettings(enabled: true, leashM: 50, lowBattery: null));
      c.deviceId = 'x';
      c.state = CollarState.connected;
      final now = DateTime.now();
      a.setHandler(home);
      c.handleEvents([const MeshMyInfo(4), MeshPositionEvent(4, MeshPosition(50.002, 20, time: now))], now: now);
      a.check(now: now);
      c.handleEvents([MeshPositionEvent(4, MeshPosition(50.0021, 20, time: now.add(const Duration(seconds: 5))))],
          now: now.add(const Duration(seconds: 5)));
      a.check(now: now.add(const Duration(seconds: 5)));
      expect(got.single.kind, AlertKind.leash);
      expect(a.history, hasLength(1));
      a.onAlert = null;
      await a.save(AlertSettings());
    });
  });
}

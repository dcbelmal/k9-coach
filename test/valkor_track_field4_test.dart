import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:k9_coach/collar/collar_link.dart';
import 'package:k9_coach/collar/distance_view.dart';
import 'package:k9_coach/collar/dog_alerts.dart';
import 'package:k9_coach/collar/mesh_proto.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/gps/phone_location.dart';
import 'package:k9_coach/gps/recorder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testy regresyjne z czwartego testu terenowego T1000-E (0.25.0):
/// błędne 113 m po wyjściu z budynku (~25 s do poprawnej odległości),
/// pakiety sprzed 5 godzin oznaczone jako bieżące, 15 s przerwy GPS
/// telefonu, ujemny wiek pakietu (różnica zegarów), brak podkładu mapy.

final t0 = DateTime(2026, 11, 25, 6);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
const _m = 111195.0;
double north(double m) => 50 + m / _m;

double noise(int i, double amp) => amp * math.sin(i * 2.399) * math.cos(i * 0.731);

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

MeshPositionEvent ev(double lat, DateTime fix, int packet, {double? speedMs = 0.3, DateTime? sent}) =>
    MeshPositionEvent(1, MeshPosition(lat, 20, time: fix, seq: 1, hdop: 0.6, speedMs: speedMs, sentTime: sent),
        packetId: packet);

Uint8List posCfg({int broadcast = 5, int gps = 2}) => (PbWriter()
      ..varint(1, broadcast)
      ..varint(4, 1)
      ..varint(5, gps)
      ..varint(7, 811)
      ..varint(13, 1))
    .toBytes();

Uint8List loraCfg({int preset = 6}) => (PbWriter()
      ..varint(1, 1)
      ..varint(2, preset)
      ..varint(7, 3) // EU_868
      ..varint(8, 3)
      ..varint(9, 1))
    .toBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late CollarLink c;
  final loc = PhoneLocation.instance;

  void phone(double lat, num s, {double acc = 4, double speed = 0}) =>
      loc.onPosition(pos(lat, at(s), acc: acc, speed: speed), now: at(s));
  DistanceView view(num s) => DistanceView.of(c, CollarLink.activeDog(), now: at(s));

  setUp(() async {
    c = CollarLink.instance..resetForTest();
    c.deviceId = 'x';
    c.state = CollarState.connected;
    c.handleEvents([const MeshMyInfo(1)], now: at(0));
    HandlerTrack.instance.clear();
    await loc.resetForTest();
    DogAlerts.instance.resetForTest();
  });
  tearDown(() async {
    c.resetForTest();
    await loc.resetForTest();
    GpsServices.reset();
    FastModeExperiment.clock = DateTime.now;
  });

  group('Stabilizacja pozycji GPS', () {
    test('błędna pierwsza pozycja trackera 113 m: bez liczby i alarmu, poprawna po 2 pomiarach', () async {
      final got = <DogAlert>[];
      final a = DogAlerts.instance..onAlert = got.add;
      await a.save(AlertSettings(enabled: true, leashM: 20, lowBattery: null));
      int? firstDistance;
      final states = <int, DistanceView>{};
      for (var s = 0; s <= 40; s++) {
        phone(north(noise(s, 1)), s);
        if (s % 5 == 0 && s >= 5) {
          final lat = s == 5 ? north(113) : north(2 + noise(s, 0.5));
          c.handleEvents([ev(lat, at(s), s)], now: at(s));
          a.check(now: at(s));
        }
        final v = view(s);
        states[s] = v;
        if (v.hasDistance) {
          firstDistance ??= s;
          expect(v.m!, lessThan(15), reason: 'fałszywa odległość po $s s');
        } else if (s >= 5) {
          expect(v.text, isNot(contains('113')));
        }
      }
      expect(states[5]!.state, DistanceState.stabilizing);
      expect(states[5]!.text, 'Stabilizacja GPS'); // 0.27.2: tekst ze specyfikacji
      // Skok 111 m w 5 s – seria od nowa; 0.27.2 nazywa to wprost
      // „Podejrzana pozycja GPS” (dawniej „ustalanie”). Nadal bez liczby.
      expect(states[10]!.state, anyOf(DistanceState.stabilizing, DistanceState.suspect));
      expect(states[10]!.hasDistance, isFalse);
      expect(c.dog!.trust.jumps, 1);
      // Po skoku filtr Kalmana zaczął od nowa: poprawna odległość po 2. spójnym
      // pomiarze (15 s), a nie po ~25 s wleczenia się za błędną pozycją.
      expect(firstDistance, 15);
      expect(got.where((e) => e.kind == AlertKind.leash), isEmpty);
      a.onAlert = null;
      await a.save(AlertSettings());
    });

    test('ustalona pozycja, potem dwa zgodne pomiary daleko: pojedynczy skok odrzucony, nowe miejsce przyjęte', () {
      for (var s = 0; s <= 20; s += 5) {
        c.handleEvents([ev(north(0), at(s), s)], now: at(s));
      }
      expect(c.dog!.trust.stable, isTrue);
      c.handleEvents([ev(north(500), at(25), 25)], now: at(25));
      expect(c.diag.rejected[FixReject.jump], 1);
      c.handleEvents([ev(north(505), at(30), 30)], now: at(30));
      expect(c.dog!.fix!.lat, north(505));
      expect(c.dog!.trust.stable, isFalse); // nowe miejsce – ustalane od nowa
    });

    test('wyjście z budynku i start treningu: bez punktów trasy i dystansu z błędnych pozycji', () {
      final r = TrackRecorder.instance
        ..state = RecState.running
        ..segments = [[]]
        ..meters = 0;
      void both(double lat, int s, {double acc = 5, double speed = 0}) {
        phone(lat, s, acc: acc, speed: speed);
        r.onPosition(pos(lat, at(s), acc: acc, speed: speed));
      }

      // W budynku: słaba dokładność.
      for (var s = 0; s < 10; s++) {
        both(north(30 + noise(s, 5)), s, acc: 50);
      }
      // Tuż po wyjściu: GPS „pewny siebie”, ale 113 m obok.
      both(north(113), 10, acc: 10);
      both(north(113), 11, acc: 10);
      expect(r.allPoints, isEmpty);
      expect(view(11).hasDistance, isFalse);
      // Poprawne pozycje: marsz 1,4 m/s.
      for (var s = 12; s <= 60; s++) {
        both(north((s - 12) * 1.4), s, speed: 1.4);
      }
      expect(loc.trust.stable, isTrue);
      expect(loc.trust.jumps, 1);
      expect(r.allPoints.every((p) => p.latitude < north(80)), isTrue);
      expect(r.meters, closeTo((60 - 14) * 1.4, 8));
      r.state = RecState.idle;
    });

    test('start ze słabym GPS: bez odległości, pojawia się od razu po 3 dobrych pomiarach', () {
      int? first;
      for (var s = 0; s <= 30; s++) {
        phone(north(noise(s, 4)), s, acc: s < 20 ? 35 : 5);
        if (s % 5 == 0 && s >= 5) c.handleEvents([ev(north(3), at(s), s)], now: at(s));
        final v = view(s);
        if (s < 20) expect(v.hasDistance, isFalse, reason: 'po $s s');
        if (v.hasDistance) first ??= s;
      }
      expect(loc.trust.why, isNull);
      expect(first, 22); // bez sztywnego czekania
    });
  });

  group('Pakiety historyczne', () {
    test('pakiety sprzed 5 godzin przy pierwszym połączeniu: poprzednia sesja, nie na żywo', () async {
      c.sessionStart = at(0);
      c.markOpenedForTest(at(0));
      final got = <CollarFix>[];
      final sub = c.fixes.listen(got.add);
      for (var i = 0; i < 10; i++) {
        c.handleEvents([ev(north(5000.0 + i), at(-5 * 3600 + i * 5), 100 + i)], now: at(1 + i * 0.1));
      }
      expect(c.diag.previousSession, 10);
      expect(c.diag.rejected[FixReject.previousSession], 10);
      expect(c.dog?.fix, isNull);
      expect(c.dog?.lastHistorical, isNull);
      expect(c.status(now: at(2)), isNot(DogLink.live));
      expect(view(2).state, DistanceState.noDog);
      expect(c.dog!.trust.streak, 0); // nie ruszają oceny wiarygodności
      // W dzienniku zostają z prawdziwym wiekiem (ok. 5 h).
      expect(c.diag.log, hasLength(10));
      final e = c.diag.log.first;
      expect(e.receivedAt.difference(e.fixAt!).inSeconds, closeTo(5 * 3600, 2));
      expect(c.diag.csv(), contains('pakiety_poprzedniej_sesji;10'));
      // Bieżąca pozycja działa normalnie.
      c.handleEvents([ev(north(2), at(5), 200)], now: at(5.3));
      c.handleEvents([ev(north(2), at(10), 201)], now: at(10.3));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got, hasLength(2));
      expect(c.status(now: at(11)), DogLink.live);
    });

    test('trening: stare pakiety nie trafiają do trasy ani dystansu psa', () {
      final r = TrackRecorder.instance
        ..state = RecState.running
        ..segments = [[]]
        ..dogSegments = [[]]
        ..dogMeters = 0;
      c.sessionStart = at(0);
      c.markOpenedForTest(at(0));
      final sub = c.fixes.listen(r.onDogFix);
      for (var i = 0; i < 5; i++) {
        c.handleEvents([ev(north(5000.0 + i * 50), at(-5 * 3600 + i * 5), 100 + i)], now: at(1));
      }
      expect(r.dogPoints, isEmpty);
      expect(r.dogMeters, 0);
      unawaited(sub.cancel());
      r.state = RecState.idle;
    });
  });

  group('GPS telefonu: przerwy', () {
    test('przerwa 15 s w trakcie śledzenia: osobno od startu, potem ponowna stabilizacja', () {
      c.handleEvents([ev(north(3), at(0), 1)], now: at(0));
      phone(north(0), 0);
      phone(north(0), 6); // przerwa przy starcie (pozycja jeszcze nieustalona)
      for (var s = 7; s <= 40; s++) {
        phone(north(noise(s, 1)), s);
        if (s % 5 == 0) c.handleEvents([ev(north(3), at(s), s)], now: at(s));
      }
      expect(view(40).hasDistance, isTrue);
      phone(north(1), 55); // 15 s bez pomiaru
      c.handleEvents([ev(north(3), at(55), 55)], now: at(55));
      expect(loc.maxGapInitSec, closeTo(6, 0.01));
      expect(loc.maxGapTrackingSec, closeTo(15, 0.01));
      expect(loc.gaps.last.init, isFalse);
      // Po przerwie dłuższej niż 10 s pozycja jest ustalana od nowa.
      expect(view(55).state, DistanceState.stabilizing);
      phone(north(1), 56);
      phone(north(1), 57);
      expect(view(57).hasDistance, isTrue);
      expect(loc.csvLines().join('\n'), contains('najdluzsza_przerwa_sledzenie_s;15'));
    });

    group('subskrypcja', () {
      late StreamController<Position> ctrl;
      setUp(() {
        ctrl = StreamController<Position>.broadcast();
        GpsServices.serviceEnabled = () async => true;
        GpsServices.checkPermission = () async => LocationPermission.whileInUse;
        PhoneLocation.streamFactory = (s) => ctrl.stream;
        PhoneLocation.clock = () => at(0);
      });
      tearDown(() => ctrl.close());

      test('restart po 8 s ciszy (zamiast 12 s) i czas do pierwszego pomiaru', () async {
        await loc.acquire('valkor_track');
        loc.onPosition(pos(50, at(1)), now: at(1));
        loc.tick(at(9));
        expect(loc.restarts, 0);
        loc.tick(at(9.5));
        await Future<void>.delayed(Duration.zero);
        expect(loc.restarts, 1);
        loc.onPosition(pos(50, at(11)), now: at(11));
        expect(loc.lastRestartLatencySec, closeTo(1.5, 0.01));
        expect(loc.gaps.last.afterRestart, isTrue);
        await loc.release('valkor_track');
      });
    });
  });

  group('Zegar telefonu i trackera', () {
    test('wysłanie „później” niż odbiór: różnica zegarów, wiek nieujemny, surowy czas zachowany', () {
      for (var i = 0; i < 6; i++) {
        final fix = at(i * 5);
        c.handleEvents([ev(north(2), fix, 10 + i, sent: at(i * 5 + 0.4))], now: at(i * 5 + 0.3));
      }
      expect(c.diag.clockOffsetSec, closeTo(-0.1, 0.001));
      final f = c.dog!.fix!;
      expect(f.rawFixAt, at(25)); // surowy czas z pakietu bez zmian
      expect(f.timeIsFix, isTrue);
      expect(f.lagSec, greaterThanOrEqualTo(0));
      expect(c.diag.lags.every((l) => l >= 0), isTrue);
      expect(c.diag.log.last.fixAt, at(25)); // dziennik: surowy czas
      expect(c.diag.csv(), contains('roznica_telefon_tracker_s;-0.10'));
    });

    test('pomiar 1,5 s „z przyszłości”: przyjęty jako aktualny, wiek 0', () {
      c.handleEvents([ev(north(2), at(100), 1)], now: at(98.5));
      final f = c.dog!.fix!;
      expect(f.timeIsFix, isTrue);
      expect(f.fixAt, at(98.5));
      expect(f.lagSec, 0);
      expect(c.status(now: at(99)), DogLink.live);
    });
  });

  group('Podkład mapy', () {
    final h = TileHealth.instance;
    setUp(h.resetForTest);
    tearDown(h.resetForTest);

    test('warstwa kafli: obsługa błędów, ponawianie i pamięć podręczna', () {
      final w = GpsServices.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', 19, NetworkTileProvider());
      expect(w.errorTileCallback, isNotNull);
      expect(w.reset, isNotNull);
      expect(w.evictErrorTileStrategy, EvictErrorTileStrategy.notVisibleRespectMargin);
      expect(w.tileBuilder, isNotNull);
    });

    test('błędy kafli: komunikat po 3 z rzędu, ponawianie z rosnącą przerwą, powrót po udanym', () async {
      final resets = <void>[];
      final sub = h.resetStream.listen(resets.add);
      h.onError(null, Exception('HTTP request failed, statusCode: 403'));
      h.onError(null, Exception('x'));
      expect(h.failing, isFalse);
      h.onError(null, Exception('HTTP request failed, statusCode: 403'));
      expect(h.failing, isTrue);
      expect(h.nextRetryAt, isNotNull);
      expect(h.retryDelaySec, 10);
      h.retryNow();
      await Future<void>.delayed(Duration.zero);
      expect(resets, hasLength(1));
      expect(h.retryDelaySec, 20);
      h.markLoaded();
      expect(h.failing, isFalse);
      expect(h.retryDelaySec, 10);
      expect(TileHealth.shortError(Exception('SocketException: Failed host lookup')), 'brak połączenia z internetem');
      expect(h.csvLines().join('\n'), contains('kafle_bledy;3'));
      await sub.cancel();
    });

    testWidgets('brak kafli: komunikat na mapie, trasa nadal widoczna', (tester) async {
      Widget app(bool consent) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: Stack(children: [
                  const Positioned.fill(child: ColoredBox(key: ValueKey('route'), color: Colors.orange)),
                  TileNotice(consent: consent, onEnable: () {}),
                ]),
              ),
            ),
          );
      await tester.pumpWidget(app(true));
      expect(find.byKey(const ValueKey('tile-notice')), findsNothing);
      for (var i = 0; i < 3; i++) {
        h.onError(null, Exception('SocketException'));
      }
      await tester.pump();
      expect(find.textContaining('Podkład mapy niedostępny'), findsOneWidget);
      expect(find.byKey(const ValueKey('route')), findsOneWidget);
      expect(find.text('Ponów'), findsOneWidget);
      h.markLoaded();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tile-notice')), findsNothing);
      // Bez zgody na mapę: informacja i przycisk włączenia.
      await tester.pumpWidget(app(false));
      expect(find.textContaining('Podkład mapy wyłączony'), findsOneWidget);
      expect(find.text('Włącz mapę'), findsOneWidget);
      h.resetForTest();
    });
  });

  group('Tryb szybkiego śledzenia (eksperyment)', () {
    late List<Uint8List> sent;
    setUp(() {
      sent = [];
      c.writeOverride = (d) async => sent.add(d);
      c.handleEvents([MeshConfigEvent(2, posCfg()), MeshConfigEvent(6, loraCfg()), const MeshConfigComplete(1)]);
      FastModeExperiment.clock = () => at(99);
    });

    Future<void> confirm({required int broadcast, required int gps}) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final id = await c.verifyRead();
      c.handleEvents([MeshConfigEvent(2, posCfg(broadcast: broadcast, gps: gps)), MeshConfigEvent(6, loraCfg()), MeshConfigComplete(id)]);
    }

    void dogEvery(double sec, int n) {
      for (var i = 0; i <= n; i++) {
        final t = 100 + i * sec;
        c.handleEvents([ev(north(1), at(t), 500 + i)], now: at(t + 0.3));
      }
    }

    test('domyślna konfiguracja sportowa bez zmian (5 s)', () {
      expect(TrackerProfile.sport.broadcastSecs, 5);
      expect(TrackerProfile.sport.gpsUpdateSecs, 2);
      expect(TrackerProfile.sport.preset, 6);
      expect(TrackMode.sport.profile, TrackerProfile.sport);
      expect(TrackerProfile.sport.matches(c.config), isTrue);
      // Radio: SHORT_FAST w UE pozwala na pozycję najczęściej co ~0,7 s.
      expect(c.fast.radioMinAfter(FastModeExperiment.exp1), lessThanOrEqualTo(1));
      expect(c.fast.blocker(1), isNull);
    });

    test('2 s: firmware nadal co 5 s – automatyczny powrót do 5 s z opisem ograniczenia', () async {
      expect(await c.fast.start(2), isNull);
      expect(c.fast.phase, FastPhase.applying);
      expect(sent, hasLength(1)); // tylko sekcja position (preset bez zmian)
      await confirm(broadcast: 2, gps: 1);
      expect(c.fast.phase, FastPhase.measuring);
      dogEvery(5, 12);
      expect(c.fast.resultMedianSec, 5);
      expect(c.fast.limitedByFirmware, isTrue);
      expect(c.fast.message, contains('Firmware'));
      expect(c.fast.phase, FastPhase.restoring);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(sent, hasLength(3)); // + odczyt kontrolny + zapis 5 s
      await confirm(broadcast: 5, gps: 2);
      expect(c.fast.phase, FastPhase.done);
      expect(TrackerProfile.sport.matches(c.config), isTrue);
      expect(c.fast.testSettingsActive, isFalse);
      expect(c.fast.csvLines().join('\n'), contains('wynik_cel_2_s;mediana_pomiarow=5.00'));
    });

    test('2 s osiągnięte: wynik i ręczny powrót do 5 s', () async {
      await c.fast.start(2);
      await confirm(broadcast: 2, gps: 1);
      dogEvery(2, 12);
      expect(c.fast.phase, FastPhase.done);
      expect(c.fast.resultMedianSec, 2);
      expect(c.fast.testSettingsActive, isTrue);
      // Warstwy osobno: GNSS, LoRa, Bluetooth, nowe pomiary, ekran.
      final rates = {for (final r in c.fast.rates()) r.$1: r.$2};
      expect(rates['GNSS (pomiar w trackerze)'], 'co 1 s');
      expect(rates['LoRa (rozgłaszanie)'], 'co 2 s');
      expect(rates['Nowe pomiary (czas GPS)'], 'co ~2,0 s');
      await c.fast.restore();
      expect(c.fast.phase, FastPhase.restoring);
      await confirm(broadcast: 5, gps: 2);
      expect(c.fast.phase, FastPhase.done);
      expect(TrackerProfile.sport.matches(c.config), isTrue);
    });

    test('brak pozycji w czasie testu: powrót do 5 s', () async {
      await c.fast.start(1);
      await confirm(broadcast: 1, gps: 1);
      c.fast.finishNow();
      expect(c.fast.phase, FastPhase.restoring);
      expect(c.fast.message, contains('Za mało pozycji'));
    });

    test('przy dwóch modułach test niedostępny', () async {
      c.handleEvents([const MeshNodeInfo(2, longName: 'Pies', hwModel: hwT1000E)]);
      expect(c.direct, isFalse);
      expect(await c.fast.start(2), isNotNull);
      expect(sent, isEmpty);
    });
  });
}

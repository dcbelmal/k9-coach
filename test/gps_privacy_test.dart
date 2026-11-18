import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/files/file_store.dart';
import 'package:k9_coach/gps/gps_drafts.dart';
import 'package:k9_coach/gps/online_services.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/gps/weather.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/nutrition/web_import.dart';
import 'package:k9_coach/screens/gps_screen.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_prefs.dart';

/// Atrapy usług: liczą każde użycie lokalizacji i sieci.
class Calls {
  int position = 0, weather = 0, tiles = 0, request = 0;
  (double, double)? weatherAt;
  LocationPermission perm = LocationPermission.whileInUse;

  void install() {
    GpsServices.serviceEnabled = () async => true;
    GpsServices.checkPermission = () async => perm;
    GpsServices.requestPermission = () async {
      request++;
      return perm;
    };
    GpsServices.position = () async {
      position++;
      return Position(
          latitude: 52.2297, longitude: 21.0122, timestamp: DateTime(2026), accuracy: 5, altitude: 0,
          altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
    };
    GpsServices.weather = (lat, lng) async {
      weather++;
      weatherAt = (lat, lng);
      return const Weather(12, 11, 60);
    };
    GpsServices.tiles = () {
      tiles++;
      return const SizedBox.shrink();
    };
  }
}

Widget app(Widget home) => MaterialApp(theme: K9.theme(), home: home);

GpsDraft sampleDraft(String dogId, {String session = 's1'}) => GpsDraft(
      sessionId: session,
      dogId: dogId,
      discipline: Discipline.canicross,
      startedAt: DateTime(2026, 11, 18, 17),
      seconds: 600,
      segments: [
        [
          const TrackPoint(52.0, 21.0, 0),
          const TrackPoint(52.001, 21.0, 30),
          const TrackPoint(52.002, 21.0, 60),
        ]
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    installFakeDisk();
    dir = await useTempFiles();
    OnlineConsent.instance
      ..weather = null
      ..map = null;
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'A'));
  });

  tearDown(() {
    GpsServices.reset();
    GpsDrafts.debugAfterStep = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('otwarcie ekranu GPS nie wysyła lokalizacji, pogoda i mapa dopiero po zgodzie', (tester) async {
    final c = Calls()..install();
    await tester.pumpWidget(app(const GpsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position, 0, reason: 'bez wyboru użytkownika nie pobieramy pozycji');
    expect(c.weather, 0, reason: 'bez zgody nic nie trafia do serwisu pogodowego');
    expect(c.tiles, 0, reason: 'bez zgody mapa nie pobiera kafli');
    expect(c.request, 0, reason: 'samo otwarcie nie pyta o dostęp do lokalizacji');
    expect(find.text('Pogoda online'), findsOneWidget);

    await tester.tap(find.text('Pogoda online'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(OnlineConsent.instance.weather, isTrue);
    expect(c.position, 1);
    expect(c.weather, 1);
    expect(c.tiles, 0, reason: 'zgoda na pogodę nie włącza mapy');

    await tester.tap(find.text('Mapa online'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.tiles, greaterThan(0));
  });

  testWidgets('po odmowie lokalizacji dostępny jest trening ręczny i bez GPS', (tester) async {
    final c = Calls()
      ..perm = LocationPermission.denied
      ..install();
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const GpsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.request, 1);
    expect(c.weather, 0);
    expect(find.text('Wpisz trening ręcznie'), findsOneWidget);
    expect(find.text('Trening bez GPS (tylko czas)'), findsOneWidget);
  });

  test('przerwanie nagrywania: po restarcie dokładnie jedna sesja u właściwego psa', () async {
    final a = DogProfiles.instance.activeId;
    await DogProfiles.instance.startAdding();
    await AppStore.instance.saveDog(Dog(name: 'B'));
    final b = DogProfiles.instance.activeId;

    // Nagrywanie u A, szkic zapisany okresowo, potem „zabicie” procesu.
    await GpsDrafts.save(sampleDraft(a));
    await GpsDrafts.save(sampleDraft(a)); // kolejny zapis tej samej sesji nadpisuje szkic
    await restartApp();
    final drafts = await GpsDrafts.pending();
    expect(drafts.length, 1);
    expect(drafts.single.dogId, a);

    // Odzyskanie, gdy wybrany jest pies B: trening trafia do A.
    expect(DogProfiles.instance.activeId, b);
    final t = await GpsDrafts.finalize(drafts.single);
    expect(AppStore.instance.trainings, isEmpty, reason: 'nic u psa B');
    expect(await GpsDrafts.pending(), isEmpty);
    await DogProfiles.instance.switchTo(a);
    expect(AppStore.instance.trainings.map((e) => e.id), [t.id]);
    expect(await FileStoreText.read(t.trackRef!), isNotNull);
  });

  test('przerwanie między zapisem pliku trasy a historią: ponowienia dają jeden trening i jedną trasę', () async {
    final a = DogProfiles.instance.activeId;
    final d = sampleDraft(a, session: 's2');
    await GpsDrafts.save(d);
    GpsDrafts.debugAfterStep = (step) async {
      if (step == 'track') throw StateError('proces zakończony');
    };
    await expectLater(GpsDrafts.finalize(d), throwsStateError);
    expect(AppStore.instance.trainings, isEmpty);
    await restartApp();
    final pending = await GpsDrafts.pending();
    expect(pending.single.finalizing, isTrue, reason: 'szkic zostaje do potwierdzenia zapisu w historii');

    GpsDrafts.debugAfterStep = (step) async {
      if (step == 'history') throw StateError('proces zakończony po zapisie historii');
    };
    await expectLater(GpsDrafts.finalize(pending.single), throwsStateError);
    GpsDrafts.debugAfterStep = null;
    await restartApp();
    final again = await GpsDrafts.pending();
    await GpsDrafts.finalize(again.single);
    await GpsDrafts.finalize(again.single); // jeszcze jedno ponowienie
    await restartApp();
    expect(AppStore.instance.trainings.length, 1);
    expect(await GpsDrafts.pending(), isEmpty);
    final tracks = dir.listSync().whereType<File>().where((f) => f.path.contains('trk_'));
    expect(tracks.length, 1);
  });

  group('import strony i obrazu', () {
    test('zbyt duża odpowiedź bez Content-Length jest przerywana', () async {
      var sent = 0;
      final client = MockClient.streaming((req, _) async {
        final stream = Stream<List<int>>.periodic(const Duration(microseconds: 1), (_) {
          sent += 64 * 1024;
          return List<int>.filled(64 * 1024, 0x61);
        }).take(200); // 12,8 MB
        return http.StreamedResponse(stream, 200, headers: {'content-type': 'text/html'});
      });
      final r = await WebImport.fromInput('https://example.test/karma', client: client);
      expect(r.fetched, isFalse);
      expect(sent, lessThan(WebImport.maxPageBytes + 3 * 64 * 1024), reason: 'odbiór przerwany po limicie');
    });

    test('uszkodzony obraz jest odrzucany, poprawny przyjmowany', () async {
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR4nGP8z8Dwn4GKgImahhEMAAAPXQIBCVXK4gAAAABJRU5ErkJggg==');
      Uint8List? imageBytes;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('.jpg')) {
          return http.Response.bytes(imageBytes!, 200, headers: {'content-type': 'image/jpeg'});
        }
        return http.Response('<html><head><meta property="og:image" content="/foto.jpg"></head><body>Białko 30%</body></html>',
            200, headers: {'content-type': 'text/html; charset=utf-8'});
      });
      var decodeCalls = 0;
      WebImport.canDecode = (b) async {
        decodeCalls++;
        return true;
      };
      imageBytes = Uint8List.fromList(List.generate(5000, (i) => (i * 37) % 256)); // nie obraz
      final bad = await WebImport.fromInput('https://example.test/karma', client: client);
      expect(bad.fetched, isTrue);
      expect(bad.image, isNull);
      expect(decodeCalls, 0);

      imageBytes = Uint8List.fromList(png);
      expect(WebImport.imageInfo(imageBytes), ('png', 16, 16));
      expect((await WebImport.fromInput('https://example.test/karma', client: client)).image, isNotNull);

      WebImport.canDecode = (b) async => false; // nagłówek dobry, treść uszkodzona
      expect((await WebImport.fromInput('https://example.test/karma', client: client)).image, isNull);
    });
  });
}

/// Odczyt pliku trasy przez FileStore.
class FileStoreText {
  static Future<String?> read(String ref) => FileStore.readText(ref);
}

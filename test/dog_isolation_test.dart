import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/files/file_refs.dart';
import 'package:k9_coach/files/file_store.dart';
import 'package:k9_coach/gallery/gallery_store.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/notifications.dart';
import 'package:k9_coach/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_prefs.dart';

Future<String> addDog(String name) async {
  await DogProfiles.instance.startAdding();
  await AppStore.instance.saveDog(Dog(name: name));
  return DogProfiles.instance.activeId;
}

bool exists(Directory dir, String ref) => File('${dir.path}/${ref.substring(5)}').existsSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    installFakeDisk();
    dir = await useTempFiles();
    DogProfiles.pendingWait = const Duration(seconds: 10);
    GalleryStore.saveFile = FileStore.save;
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> setupTwoDogs() async {
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'A'));
    await addDog('B');
  }

  for (final waitForPending in [true, false]) {
    test('opóźniony zapis zdjęcia psa A kończy się u A po przełączeniu na B '
        '(${waitForPending ? 'przełączenie czeka' : 'przełączenie nie czeka'})', () async {
      await setupTwoDogs();
      final b = DogProfiles.instance.activeId;
      await DogProfiles.instance.switchTo(DogProfiles.mainId); // A
      if (!waitForPending) DogProfiles.pendingWait = Duration.zero;

      final release = Completer<void>();
      GalleryStore.saveFile = (bytes) async {
        await release.future; // zapis pliku „trwa”
        return FileStore.save(bytes);
      };
      final adding = GalleryStore.instance.add(Uint8List.fromList([1, 2, 3]));
      final switching = DogProfiles.instance.switchTo(b);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      await adding;
      await switching;

      expect(DogProfiles.instance.activeId, b);
      expect(GalleryStore.instance.photos, isEmpty, reason: 'zdjęcie A nie trafia do galerii B');
      await restartApp();
      expect(GalleryStore.instance.photos, isEmpty);
      await DogProfiles.instance.switchTo(DogProfiles.mainId);
      expect(GalleryStore.instance.photos.length, 1);
      expect(exists(dir, GalleryStore.instance.photos.single.ref), isTrue);
    });
  }

  test('usunięcie psa A usuwa jego trasę, a trasa i przypomnienie B działają', () async {
    await restartApp();
    final now = DateTime.now();
    await AppStore.instance.saveDog(Dog(name: 'A'));
    final trackA = await FileStore.saveText('{"v":1,"s":[],"laps":[]}');
    await AppStore.instance.upsertTraining(
        TrainingSession(id: 'ta', discipline: Discipline.canicross, date: now, trackRef: trackA));
    await AppStore.instance.upsertHealth(HealthRecord(
        id: 'ha', category: HealthCategory.vaccination, title: 'Szczepienie A', date: now, nextDue: now.add(const Duration(days: 30))));

    final b = await addDog('B');
    final trackB = await FileStore.saveText('{"v":1,"s":[],"laps":[]}', name: 'trk_b.json');
    await AppStore.instance.upsertTraining(
        TrainingSession(id: 'tb', discipline: Discipline.canicross, date: now, trackRef: trackB));
    await AppStore.instance.upsertHealth(HealthRecord(
        id: 'hb', category: HealthCategory.vaccination, title: 'Szczepienie B', date: now, nextDue: now.add(const Duration(days: 40))));

    // Przełączenie i edycja B nie kasują przypomnień A.
    await DogProfiles.instance.switchTo(DogProfiles.mainId);
    await DogProfiles.instance.switchTo(b);
    await AppStore.instance.saveDog(AppStore.instance.dog!..notes = 'edycja');
    final p = await SharedPreferences.getInstance();
    var plan = Notifications.mergedPlan(p, DogProfiles.instance.ids, b, Notifications.buildPlan(AppStore.instance), now);
    expect(plan.once.where((o) => o.$3.contains('Szczepienie A')), isNotEmpty);
    expect(plan.once.where((o) => o.$3.contains('Szczepienie B')), isNotEmpty);
    // Bez duplikatów, w limicie systemu.
    expect(plan.once.length, plan.once.map((o) => '${o.$1}|${o.$2}|${o.$3}').toSet().length);
    expect(plan.once.length + plan.daily.length, lessThanOrEqualTo(Notifications.maxScheduled));

    // Usunięcie A.
    await DogProfiles.instance.switchTo(DogProfiles.mainId);
    await DogProfiles.instance.deleteActive();
    expect(exists(dir, trackA), isFalse, reason: 'plik trasy A usunięty');
    expect(exists(dir, trackB), isTrue);

    await restartApp();
    expect(DogProfiles.instance.ids, [b]);
    expect(AppStore.instance.dog!.name, 'B');
    final tb = AppStore.instance.trainings.single;
    expect(await FileStore.readText(tb.trackRef!), isNotNull, reason: 'trasa B działa');
    plan = Notifications.mergedPlan(await SharedPreferences.getInstance(), DogProfiles.instance.ids, b,
        Notifications.buildPlan(AppStore.instance), now);
    expect(plan.once.where((o) => o.$3.contains('Szczepienie B')), isNotEmpty);
    expect(plan.once.where((o) => o.$3.contains('Szczepienie A')), isEmpty);
  });

  test('sprzątanie po usunięciu psa dokańcza się po restarcie', () async {
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'A'));
    final b = await addDog('B');
    final trackB = await FileStore.saveText('{}', name: 'trk_b.json');
    await AppStore.instance.upsertTraining(TrainingSession(id: 'tb', discipline: Discipline.walk, date: DateTime.now(), trackRef: trackB));
    await DogProfiles.instance.switchTo(DogProfiles.mainId);

    // Symulacja: proces zakończony po zapisaniu dziennika i listy psów, przed usunięciem danych.
    final disk = SharedPreferencesStoreRef.disk;
    disk.put('valkor_cleanup_v1', jsonEncode([
      {'dog': b, 'files': [trackB]}
    ]));
    disk.put('valkor_dogs_v1', jsonEncode({'ids': ['main'], 'active': 'main', 'returnTo': null}));
    await restartApp();
    expect(disk.raw('k9coach_data_v1@$b'), isNull);
    expect(disk.raw('valkor_cleanup_v1'), isNull);
    expect(exists(dir, trackB), isFalse);
    expect(AppStore.instance.dog!.name, 'A');
  });

  test('pliki po starszych wersjach: sprzątane tylko bez właściciela i gdy wszystkie profile są czytelne', () async {
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'A'));
    final used = await FileStore.saveText('{}', name: 'trk_used.json');
    await AppStore.instance.upsertTraining(TrainingSession(id: 't', discipline: Discipline.walk, date: DateTime.now(), trackRef: used));
    final orphan = await FileStore.saveText('{}', name: 'trk_orphan.json');
    final fresh = await FileStore.saveText('{}', name: 'trk_fresh.json');
    final old = DateTime.now().subtract(const Duration(days: 3));
    for (final r in [used, orphan]) {
      File('${dir.path}/${r.substring(5)}').setLastModifiedSync(old);
    }
    // Nieczytelny zapis innego psa – właściciel części plików nieznany: nic nie usuwamy.
    final disk = SharedPreferencesStoreRef.disk;
    disk.put('k9coach_data_v1@dX', '{zepsute');
    SharedPreferences.resetStatic();
    expect(await DogProfiles.instance.sweepOrphanFiles(), 0);
    expect(exists(dir, orphan), isTrue);

    disk.disk.remove('flutter.k9coach_data_v1@dX');
    SharedPreferences.resetStatic();
    expect(await DogProfiles.instance.sweepOrphanFiles(), 1);
    expect(exists(dir, orphan), isFalse);
    expect(exists(dir, used), isTrue);
    expect(exists(dir, fresh), isTrue, reason: 'świeży plik może należeć do zapisu w toku');
  });

  test('operacje na plikach tylko dla prawidłowych referencji w katalogu aplikacji', () async {
    final outside = File('${dir.parent.path}/poza.txt')..writeAsStringSync('x');
    expect(FileStore.isValidRef('file:../poza.txt'), isFalse);
    expect(FileStore.isValidRef('file:a/b.json'), isFalse);
    expect(FileStore.isValidRef('file:trk_1.json'), isTrue);
    await FileStore.delete('file:../poza.txt');
    expect(outside.existsSync(), isTrue);
    expect(await FileStore.readText('file:../poza.txt'), isNull);
    expect(FileRefs.extract('{"track":"file:trk_1.json","x":"file:../a"}'), {'file:trk_1.json'});
    outside.deleteSync();
  });
}

/// Dostęp do atrapy dysku zainstalowanej w setUp.
class SharedPreferencesStoreRef {
  static FakeDisk get disk => currentDisk!;
}

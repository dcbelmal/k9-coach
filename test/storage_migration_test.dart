import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/storage/safe_prefs.dart';
import 'package:k9_coach/store.dart';

import 'helpers/fake_prefs.dart';

/// Profil zapisany przez starszą wersję (bez pola „schema”), z jednym
/// nieczytelnym treningiem (dyscyplina, której ta wersja nie zna).
Map<String, dynamic> oldProfile() => {
      'dog': {'name': 'Gamora', 'breed': 'Malinois', 'female': true, 'weightKg': 20.5, 'bcs': 4},
      'weights': [
        {'id': 'w1', 'date': '2026-10-01T00:00:00.000', 'kg': 20.5}
      ],
      'health': [
        {'id': 'h1', 'category': 'vaccination', 'title': 'Wścieklizna', 'date': '2026-01-10T00:00:00.000', 'nextDue': '2027-01-10T00:00:00.000'}
      ],
      'trainings': [
        {'id': 't1', 'discipline': 'canicross', 'date': '2026-11-01T17:00:00.000', 'durationMin': 40, 'distanceKm': 6.2, 'rpe': 6},
        {'id': 'tX', 'discipline': 'agility', 'date': '2026-11-02T17:00:00.000', 'durationMin': 30, 'note': 'z nowszej wersji'},
        {'id': 't2', 'discipline': 'obedience', 'date': '2026-11-03T17:00:00.000', 'durationMin': 25.0, 'rpe': 5},
      ],
      'events': [],
      'shows': [],
      'documents': [
        {'id': 'd1', 'type': 'pedigree', 'title': 'Rodowód ZKwP', 'number': 'PKR.I-1', 'images': []}
      ],
      'gear': [],
      'goals': [
        {'id': 'c1', 'type': 'exam', 'title': 'IGP 1', 'start': '2026-06-01T00:00:00.000', 'manual': 0.6}
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stary profil z nieczytelnym treningiem: nic nie ginie, waga się zapisuje, restart', () async {
    final original = jsonEncode(oldProfile());
    final disk = installFakeDisk({'k9coach_data_v1': original});
    await restartApp();
    final s = AppStore.instance;

    // Poprawne wpisy odczytane, nieczytelny zachowany i zgłoszony.
    expect(s.locked, isFalse);
    expect(s.dog!.name, 'Gamora');
    expect([for (final t in s.trainings) t.id]..sort(), ['t1', 't2']);
    expect(s.trainings.firstWhere((t) => t.id == 't2').durationMin, 25); // 25.0 ze starszego zapisu
    expect(s.documents.single.title, 'Rodowód ZKwP');
    expect(s.goals.single.title, 'IGP 1');
    expect(s.health.single.title, 'Wścieklizna');
    expect(s.unreadableCount, 1);
    expect(DataHealth.instance.issues.values.single.unreadable, 1);
    // Oryginalne bajty zachowane w kopii odzysku – bajt w bajt.
    final copyKey = SafePrefs.recoveryKey('k9coach_data_v1', original);
    expect(disk.raw(copyKey), original);
    expect(DogProfiles.instance.ids, ['main']);

    // Dopisanie wagi.
    await s.addWeight(WeightEntry(id: 'w2', date: DateTime(2026, 11, 18), kg: 21.0));
    final saved = jsonDecode(disk.raw('k9coach_data_v1')!) as Map<String, dynamic>;
    expect(saved['schema'], DogDataDoc.schemaVersion);
    final rawTrainings = saved['trainings'] as List;
    expect(rawTrainings.length, 3, reason: 'nieczytelny trening wraca do zapisu');
    expect(rawTrainings.firstWhere((e) => e['id'] == 'tX'), oldProfile()['trainings'][1],
        reason: 'nieczytelny wpis zapisany bez żadnej zmiany');
    expect((saved['documents'] as List).length, 1);
    expect((saved['goals'] as List).length, 1);
    expect((saved['weights'] as List).length, 2);

    // Restart: wszystko na miejscu, kopia oryginału nadal istnieje.
    await restartApp();
    expect(AppStore.instance.weights.length, 2);
    expect(AppStore.instance.trainings.length, 2);
    expect(AppStore.instance.unreadableCount, 1);
    expect(AppStore.instance.documents.length, 1);
    expect(AppStore.instance.goals.length, 1);
    expect(disk.raw(copyKey), original);
  });

  test('uszkodzony profil: zapis zablokowany, oryginał bajt w bajt, odzysk poprawnych wpisów', () async {
    // Profil psa w złym formacie (np. po błędzie innej wersji) – całości nie da się bezpiecznie użyć.
    final p = oldProfile()..['dog'] = 'zepsute';
    final original = jsonEncode(p);
    final disk = installFakeDisk({'k9coach_data_v1': original});
    await restartApp();
    final s = AppStore.instance;
    expect(s.locked, isTrue);
    expect(s.dog, isNull);
    expect(DataHealth.instance.hasLocked, isTrue);
    // Pies nadal jest na liście (do odzyskania), a nie „znika”.
    expect(DogProfiles.instance.ids, ['main']);
    expect(DogProfiles.instance.peek('main')!.name, contains('dane do odzyskania'));

    // Próba zapisu wagi nie nadpisuje danych.
    await expectLater(s.addWeight(WeightEntry(id: 'w9', date: DateTime(2026, 11, 18), kg: 21)),
        throwsA(isA<StorageLockedException>()));
    expect(disk.raw('k9coach_data_v1'), original);

    // Restart – dalej zablokowany, oryginał nietknięty.
    await restartApp();
    expect(AppStore.instance.locked, isTrue);
    expect(disk.raw('k9coach_data_v1'), original);
    expect(disk.raw(SafePrefs.recoveryKey('k9coach_data_v1', original)), original);

    // Ścieżka odzysku: poprawne wpisy wracają, nieczytelne zostają zachowane.
    expect(await AppStore.instance.salvage(), isTrue);
    expect(AppStore.instance.locked, isFalse);
    expect(AppStore.instance.trainings.length, 2);
    expect(AppStore.instance.documents.length, 1);
    expect(AppStore.instance.goals.length, 1);
    expect(disk.raw(SafePrefs.recoveryKey('k9coach_data_v1', original)), original);
    await restartApp();
    expect(AppStore.instance.trainings.length, 2);
    expect(AppStore.instance.unreadableCount, 1);
  });

  test('zapis z nowszej wersji aplikacji (wyższy schemat) nie jest nadpisywany', () async {
    final newer = jsonEncode(oldProfile()..['schema'] = DogDataDoc.schemaVersion + 1);
    final disk = installFakeDisk({'k9coach_data_v1': newer});
    await restartApp();
    expect(AppStore.instance.locked, isTrue);
    await expectLater(AppStore.instance.saveDog(Dog(name: 'X')), throwsA(isA<StorageLockedException>()));
    expect(disk.raw('k9coach_data_v1'), newer);
  });

  test('migracja jest bezpieczna przy powtórzeniu (kilka restartów, bez zmian)', () async {
    final original = jsonEncode(oldProfile());
    final disk = installFakeDisk({'k9coach_data_v1': original});
    await restartApp();
    final writes = disk.writes;
    await restartApp();
    await restartApp();
    // Samo uruchomienie niczego nie przepisuje (poza jednorazową kopią i listą psów).
    expect(disk.writes, writes);
    expect(disk.raw('k9coach_data_v1'), original);
  });

  group('brak miejsca i przerwanie zapisu przy dodawaniu drugiego psa', () {
    test('brak miejsca: błąd zgłoszony, nic nie udaje sukcesu, ponowienie działa', () async {
      final disk = installFakeDisk({'k9coach_data_v1': jsonEncode(oldProfile())});
      await restartApp();
      final before = disk.raw('k9coach_data_v1');
      await DogProfiles.instance.startAdding();
      final newId = DogProfiles.instance.activeId;

      disk.full = true;
      await expectLater(AppStore.instance.saveDog(Dog(name: 'Luna')), throwsA(isA<StorageWriteException>()));
      // Stan w pamięci wrócił do sprzed próby – aplikacja nie pokazuje niezapisanego psa.
      expect(AppStore.instance.dog, isNull);
      expect(DogProfiles.instance.ids, ['main']);

      // Wyjątek zamiast false – to samo zachowanie.
      disk.full = false;
      disk.throwOnWrite = true;
      await expectLater(AppStore.instance.saveDog(Dog(name: 'Luna')), throwsA(isA<StorageWriteException>()));
      expect(AppStore.instance.dog, isNull);

      // Restart w trakcie: pierwszy pies nietknięty, brak „pustego” psa na liście.
      disk.throwOnWrite = false;
      await restartApp();
      expect(disk.raw('k9coach_data_v1'), before);
      expect(DogProfiles.instance.dogs.map((d) => d.$2.name), ['Gamora']);
      expect(DogProfiles.instance.activeId, newId, reason: 'dodawanie można dokończyć');

      // Ponowienie po zwolnieniu miejsca.
      await AppStore.instance.saveDog(Dog(name: 'Luna'));
      expect(DogProfiles.instance.ids, ['main', newId]);
      await restartApp();
      expect(DogProfiles.instance.dogs.map((d) => d.$2.name), ['Gamora', 'Luna']);
    });

    test('przerwanie między zapisem profilu a zapisem listy psów: pies wraca na listę po restarcie', () async {
      final disk = installFakeDisk({'k9coach_data_v1': jsonEncode(oldProfile())});
      await restartApp();
      await DogProfiles.instance.startAdding();
      final newId = DogProfiles.instance.activeId;
      disk.failKeys.add('valkor_dogs_v1'); // profil zapisany, lista psów – nie
      await expectLater(AppStore.instance.saveDog(Dog(name: 'Luna')), throwsA(isA<StorageWriteException>()));
      expect(disk.raw('k9coach_data_v1@$newId'), isNotNull);

      disk.failKeys.clear();
      await restartApp();
      expect(DogProfiles.instance.ids, containsAll(['main', newId]));
      expect(DogProfiles.instance.dogs.map((d) => d.$2.name).toSet(), {'Gamora', 'Luna'});
      await DogProfiles.instance.switchTo('main');
      expect(AppStore.instance.dog!.name, 'Gamora');
      expect(AppStore.instance.trainings.length, 2);
    });

    test('nieudany zapis listy psów cofa przełączenie', () async {
      final disk = installFakeDisk({'k9coach_data_v1': jsonEncode(oldProfile())});
      await restartApp();
      disk.full = true;
      await expectLater(DogProfiles.instance.startAdding(), throwsA(isA<StorageWriteException>()));
      expect(DogProfiles.instance.activeId, 'main');
      expect(AppStore.instance.dog!.name, 'Gamora');
    });
  });
}

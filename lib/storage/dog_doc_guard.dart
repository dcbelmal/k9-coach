import 'package:shared_preferences/shared_preferences.dart';

import 'safe_prefs.dart';

/// Id pierwszego psa – używa starych kluczy zapisu bez dopisku.
const mainDogId = 'main';

/// Dopisek klucza zapisu dla psa ('' dla pierwszego psa).
String dogSuffix(String id) => id == mainDogId ? '' : '@$id';

/// Pilnuje jednego zapisu JSON zależnego od psa (np. galeria, cieczka):
/// – pamięta, do którego psa należą dane w pamięci (właściciel),
/// – blokuje zapis, gdy danych nie dało się odczytać (oryginał zostaje),
/// – zapisuje po kolei i cofa zmiany w pamięci, gdy zapis się nie uda.
class DogDocGuard {
  DogDocGuard(this.base, this.label);

  final String base;
  final String label;

  String owner = mainDogId;
  bool locked = false;
  String? lastGoodRaw;
  final queue = SerialQueue();

  String keyOf(String id) => '$base${dogSuffix(id)}';
  String get key => keyOf(owner);

  /// Odczyt dla psa [ownerId]. [parse] musi odczytać wszystko do zmiennych
  /// tymczasowych i rzucić wyjątek przy błędzie. Zwraca true, gdy dane są do użycia.
  Future<bool> load(SharedPreferences p, String ownerId, void Function(String? raw) parse) async {
    final k = keyOf(ownerId);
    final raw = p.getString(k);
    try {
      parse(raw);
    } catch (e) {
      logError('$label: odczyt', e);
      final backup = raw == null ? null : await SafePrefs.preserve(p, k, raw);
      owner = ownerId;
      locked = true;
      lastGoodRaw = null;
      DataHealth.instance.report(StoreIssue(key: k, store: label, locked: true, backupKey: backup, reason: e.runtimeType.toString()));
      parse(null); // pusty stan w pamięci, oryginał zostaje nietknięty
      return false;
    }
    owner = ownerId;
    locked = false;
    lastGoodRaw = raw;
    DataHealth.instance.clear(k);
    return true;
  }

  /// Zapis danych bieżącego psa. Przy błędzie [restore] przywraca ostatni dobry stan.
  Future<void> write(SharedPreferences p, String Function() encode, void Function(String? lastGood) restore) =>
      queue.run(() async {
        if (locked) {
          restore(null);
          throw StorageLockedException(key);
        }
        final encoded = encode();
        try {
          await SafePrefs.setString(p, key, encoded);
        } catch (e) {
          restore(lastGoodRaw);
          rethrow;
        }
        lastGoodRaw = encoded;
      });

  /// Zmiana zapisu innego psa niż ten w pamięci (operacja rozpoczęta przed przełączeniem).
  Future<void> writeOther(SharedPreferences p, String ownerId, String Function(String? raw) change) =>
      queue.run(() async {
        final k = keyOf(ownerId);
        await SafePrefs.setString(p, k, change(p.getString(k)));
      });
}

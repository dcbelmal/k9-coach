import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Zapis nie doszedł do skutku (brak miejsca, odmowa systemu, wyjątek).
/// Dane w pamięci telefonu zostały takie jak przed próbą.
class StorageWriteException implements Exception {
  final String key;
  final String cause; // tylko typ błędu – bez treści danych
  StorageWriteException(this.key, [Object? error]) : cause = error == null ? 'false' : error.runtimeType.toString();

  String get userMessage =>
      tr('Nie udało się zapisać. Poprzednie dane są bezpieczne. Sprawdź wolne miejsce w telefonie i spróbuj ponownie.');

  @override
  String toString() => 'StorageWriteException($key, $cause)';
}

/// Profil jest zablokowany do zapisu, bo jego danych nie dało się bezpiecznie odczytać.
class StorageLockedException implements Exception {
  final String key;
  StorageLockedException(this.key);

  String get userMessage => tr('Dane tego psa są zablokowane do zapisu, bo nie udało się ich odczytać. Otwórz „Odzyskiwanie danych”.');

  @override
  String toString() => 'StorageLockedException($key)';
}

/// Komunikat dla użytkownika dla dowolnego błędu zapisu.
String storageErrorMessage(Object e) => switch (e) {
      StorageWriteException w => w.userMessage,
      StorageLockedException l => l.userMessage,
      _ => tr('Nie udało się zapisać. Spróbuj ponownie.'),
    };

bool isStorageError(Object e) => e is StorageWriteException || e is StorageLockedException;

/// Kolejka: operacje wykonują się po kolei, nigdy równolegle.
class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() op) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await op());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }
}

/// Bezpieczne operacje na SharedPreferences.
class SafePrefs {
  /// Prefiks kopii oryginalnych bajtów danych, których nie dało się odczytać.
  static const recoveryPrefix = 'valkor_recovery_v1|';

  /// Zapis, który traktuje zarówno `false`, jak i wyjątek jako błąd.
  static Future<void> setString(SharedPreferences p, String key, String value) async {
    bool ok;
    try {
      ok = await p.setString(key, value);
    } catch (e) {
      throw StorageWriteException(key, e);
    }
    if (!ok) throw StorageWriteException(key);
  }

  static Future<void> remove(SharedPreferences p, String key) async {
    bool ok;
    try {
      ok = await p.remove(key);
    } catch (e) {
      throw StorageWriteException(key, e);
    }
    if (!ok) throw StorageWriteException(key);
  }

  /// Stabilny skrót tekstu (FNV-1a 32 bit) – do nazw kopii.
  static String hash(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String recoveryKey(String key, String raw) => '$recoveryPrefix$key|${hash(raw)}';

  /// Zachowuje oryginalne bajty pod osobnym kluczem (bezpieczne przy powtórzeniu).
  /// Zwraca klucz kopii albo null, gdy kopii nie dało się zapisać.
  static Future<String?> preserve(SharedPreferences p, String key, String raw) async {
    final k = recoveryKey(key, raw);
    if (p.getString(k) == raw) return k;
    try {
      await setString(p, k, raw);
      return k;
    } catch (e) {
      logError('Kopia odzysku', e);
      return null;
    }
  }

  /// Wszystkie kopie odzysku dla danego klucza.
  static List<String> recoveryCopies(SharedPreferences p, String key) =>
      [for (final k in p.getKeys()) if (k.startsWith('$recoveryPrefix$key|')) k]..sort();
}

/// Loguje błąd bez treści danych (tylko miejsce i typ wyjątku).
void logError(String where, Object e) {
  debugPrint('$where: ${e.runtimeType}');
}

/// Problem z odczytem danych jednego magazynu.
class StoreIssue {
  final String key; // klucz z danymi (z dopiskiem psa)
  final String store; // nazwa dla człowieka, np. „Treningi i zdrowie”
  final bool locked; // true = zapis zablokowany
  final int unreadable; // liczba zachowanych, nieodczytanych wpisów
  final String? backupKey;
  final String reason;
  const StoreIssue({
    required this.key,
    required this.store,
    required this.locked,
    this.unreadable = 0,
    this.backupKey,
    this.reason = '',
  });
}

/// Zbiera informacje o problemach z odczytem, żeby pokazać je użytkownikowi.
class DataHealth extends ChangeNotifier {
  DataHealth._();
  static final DataHealth instance = DataHealth._();

  final Map<String, StoreIssue> issues = {};

  void report(StoreIssue i) {
    issues[i.key] = i;
    notifyListeners();
  }

  void clear(String key) {
    if (issues.remove(key) != null) notifyListeners();
  }

  /// Problemy dotyczące kluczy z danym dopiskiem psa ('' = pierwszy pies).
  List<StoreIssue> forSuffix(String suffix) => [
        for (final i in issues.values)
          if (suffix.isEmpty ? !i.key.contains('@') : i.key.endsWith(suffix)) i
      ];

  bool get hasLocked => issues.values.any((i) => i.locked);
}

/// Odczyt listy rekordów: niepoprawne wpisy są zachowywane w surowej postaci,
/// a nie kasowane. Zwraca (odczytane, nieodczytane).
(List<T>, List<dynamic>) readList<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  final ok = <T>[];
  final bad = <dynamic>[];
  if (raw == null) return (ok, bad);
  if (raw is! List) throw const FormatException('not a list');
  for (final e in raw) {
    try {
      ok.add(parse(Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      bad.add(e);
    }
  }
  return (ok, bad);
}

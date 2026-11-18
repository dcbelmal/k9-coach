import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../storage/safe_prefs.dart';
import 'file_store.dart';

/// Wyszukiwanie odwołań do plików w zapisach aplikacji.
///
/// Odwołania szukamy w surowym tekście zapisów, więc działa to także dla
/// wpisów, których aplikacja nie potrafi odczytać (np. z nowszej wersji).
class FileRefs {
  static final _pattern = RegExp(r'file:[A-Za-z0-9][A-Za-z0-9_.\-]{0,120}');

  /// Szkice treningów GPS mają własne pliki – nigdy nie są „sierotami”.
  static const draftPrefix = 'file:draft_';

  static Set<String> extract(String raw) => {for (final m in _pattern.allMatches(raw)) m.group(0)!};

  /// Wszystkie odwołania w SharedPreferences, z pominięciem [exceptKeys].
  static Set<String> referenced(SharedPreferences p, {Set<String> exceptKeys = const {}}) {
    final out = <String>{};
    for (final k in p.getKeys()) {
      if (exceptKeys.contains(k)) continue;
      final v = p.get(k);
      if (v is String) {
        out.addAll(extract(v));
      } else if (v is List) {
        for (final e in v) {
          if (e is String) out.addAll(extract(e));
        }
      }
    }
    return out;
  }

  /// Odwołania zapisane w szkicach treningów GPS.
  static Future<Set<String>> draftRefs() async {
    final out = <String>{};
    for (final (ref, _) in await FileStore.listFiles()) {
      if (!ref.startsWith(draftPrefix)) continue;
      final t = await FileStore.readText(ref);
      if (t != null) out.addAll(extract(t).where((r) => r != ref));
    }
    return out;
  }

  /// Czy wszystkie zapisy psów da się odczytać jako JSON. Gdy nie – właściciel
  /// części plików jest nieustalony i niczego nie sprzątamy.
  static bool allReadable(SharedPreferences p, List<String> perDogBases) {
    for (final k in p.getKeys()) {
      if (k.startsWith(SafePrefs.recoveryPrefix)) continue;
      if (!perDogBases.any((b) => k == b || k.startsWith('$b@'))) continue;
      final v = p.get(k);
      if (v is! String) return false;
      try {
        jsonDecode(v);
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Sprząta pliki po starszych wersjach, do których nie odwołuje się żaden zapis.
  /// Pliki młodsze niż [minAge] zostają (mogą należeć do zapisu w toku).
  static Future<int> sweepOrphans(
    SharedPreferences p, {
    required bool indexReadable,
    required List<String> perDogBases,
    Duration minAge = const Duration(hours: 24),
    DateTime? now,
  }) async {
    if (!FileStore.hasFiles || !indexReadable || !allReadable(p, perDogBases)) return 0;
    final refs = referenced(p)..addAll(await draftRefs());
    final t = now ?? DateTime.now();
    var n = 0;
    for (final (ref, modified) in await FileStore.listFiles()) {
      if (ref.startsWith(draftPrefix) || refs.contains(ref)) continue;
      if (t.difference(modified) < minAge) continue;
      try {
        await FileStore.delete(ref);
        n++;
      } catch (e) {
        logError('Sprzątanie plików', e);
      }
    }
    return n;
  }
}

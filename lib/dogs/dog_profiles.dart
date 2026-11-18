import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../breeding/breeding_store.dart';
import '../files/file_refs.dart';
import '../files/file_store.dart';
import '../gallery/gallery_store.dart';
import '../gps/gps_drafts.dart';
import '../guides/guide_store.dart';
import '../heat/heat_store.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../modules/module_store.dart';
import '../notifications.dart';
import '../nutrition/nutrition_store.dart';
import '../storage/dog_doc_guard.dart';
import '../storage/safe_prefs.dart';
import '../store.dart';

/// Lista psów w aplikacji i to, który jest teraz wybrany.
///
/// Każdy pies ma własny komplet danych (trening, zdrowie, żywienie, cieczka,
/// hodowla, galeria, poradniki, moduły). Pierwszy pies (`main`) używa starych
/// kluczy zapisu, więc dane sprzed tej wersji zostają u niego bez przenoszenia.
/// Kolejne psy zapisują się pod kluczami z dopiskiem `@<id>`.
///
/// Model dostępu w tej wersji: jeden opiekun na jednym profilu użytkownika
/// telefonu. Każdy, kto może otworzyć aplikację, widzi wszystkie psy.
class DogProfiles extends ChangeNotifier {
  DogProfiles._();
  static final DogProfiles instance = DogProfiles._();

  static const _key = 'valkor_dogs_v1';
  static const _cleanupKey = 'valkor_cleanup_v1';
  static const mainId = mainDogId;

  /// Klucze wszystkich danych zależnych od psa.
  static const perDogKeys = [
    'k9coach_data_v1',
    'k9coach_nutrition_v1',
    'valkor_modules_v1',
    'valkor_heat_v1',
    'valkor_gallery_v1',
    'valkor_breeding_v1',
    'valkor_guides_v1',
    Notifications.planKey,
  ];

  SharedPreferences? _prefs;
  List<String> ids = [];
  String activeId = mainId;

  /// Pies, do którego wracamy, gdy ktoś przerwie dodawanie nowego psa.
  String? returnTo;

  /// false = listy psów nie dało się odczytać (odbudowana z zapisów psów).
  bool indexReadable = true;

  static String suffixFor(String id) => dogSuffix(id);
  String get suffix => suffixFor(activeId);
  String keyFor(String base) => '$base$suffix';

  bool get adding => !ids.contains(activeId);

  final _ops = SerialQueue();
  final Set<Future<void>> _pending = {};

  /// Jak długo przełączenie psa czeka na zakończenie zapisów w toku.
  /// Każdy zapis i tak trafia do psa, dla którego go rozpoczęto.
  @visibleForTesting
  static Duration pendingWait = const Duration(seconds: 10);

  /// Oznacza operację w toku (np. zapis zdjęcia) – przełączenie psa poczeka na nią.
  Future<T> track<T>(Future<T> Function() op) {
    final f = op();
    final done = f.then((_) {}, onError: (_) {});
    _pending.add(done);
    done.whenComplete(() => _pending.remove(done));
    return f;
  }

  Future<void> _waitPending() async {
    if (_pending.isEmpty) return;
    try {
      await Future.wait(_pending.toList()).timeout(pendingWait);
    } on TimeoutException {
      logError('Psy: zapis w toku trwa długo', 'timeout');
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    final raw = p.getString(_key);
    indexReadable = true;
    ids = [];
    activeId = mainId;
    returnTo = null;
    var changed = false;
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        ids = [for (final e in (j['ids'] as List? ?? [])) e as String];
        activeId = j['active'] as String? ?? mainId;
        returnTo = j['returnTo'] as String?;
      } catch (e) {
        logError('Psy: odczyt listy', e);
        indexReadable = false;
        await SafePrefs.preserve(p, _key, raw);
        ids = [];
        changed = true;
      }
    } else if (p.getString(AppStore.baseKey) != null) {
      // Pierwsze uruchomienie po aktualizacji: obecny pies staje się pierwszym na liście.
      ids = [mainId];
      activeId = mainId;
      changed = true;
    }
    // Spójność: pies z zapisanym profilem, którego nie ma na liście (np. proces
    // zakończył się między zapisem profilu a zapisem listy), wraca na listę.
    for (final id in _idsWithProfile(p)) {
      if (!ids.contains(id) && !_pendingCleanupIds(p).contains(id)) {
        ids.add(id);
        if (id == activeId) returnTo = null;
        changed = true;
      }
    }
    if (ids.isNotEmpty && !ids.contains(activeId) && returnTo == null) activeId = ids.first;
    if (changed) {
      try {
        await _write();
      } catch (e) {
        logError('Psy: zapis listy', e);
      }
    }
    await _runCleanup();
  }

  /// Id psów, które mają zapisany profil (pole „dog”) – także nieczytelny.
  static List<String> _idsWithProfile(SharedPreferences p) {
    final out = <String>[];
    for (final k in p.getKeys()) {
      if (k != AppStore.baseKey && !k.startsWith('${AppStore.baseKey}@')) continue;
      final id = k == AppStore.baseKey ? mainId : k.substring(AppStore.baseKey.length + 1);
      final v = p.get(k);
      if (v is! String) continue;
      try {
        final j = jsonDecode(v);
        if (j is Map && j['dog'] == null) continue;
      } catch (_) {
        // Nieczytelny zapis: zostawiamy psa na liście, żeby dało się go odzyskać.
      }
      out.add(id);
    }
    out.sort((a, b) => a == mainId ? -1 : (b == mainId ? 1 : a.compareTo(b)));
    return out;
  }

  Future<void> _write() async {
    _prefs ??= await SharedPreferences.getInstance();
    await SafePrefs.setString(_prefs!, _key, jsonEncode({'ids': ids, 'active': activeId, 'returnTo': returnTo}));
  }

  /// Zmiana listy psów z cofnięciem w pamięci, gdy zapis się nie uda.
  Future<void> _change(void Function() change) async {
    final oldIds = [...ids], oldActive = activeId, oldReturn = returnTo;
    change();
    try {
      await _write();
    } catch (e) {
      ids = oldIds;
      activeId = oldActive;
      returnTo = oldReturn;
      rethrow;
    }
  }

  /// Wywoływane po zapisaniu profilu psa – nowy pies trafia na listę.
  Future<void> registerActive() async {
    if (ids.contains(activeId)) return;
    await _change(() {
      ids.add(activeId);
      returnTo = null;
    });
    notifyListeners();
  }

  /// Odczyt profilu dowolnego psa (bez przełączania), np. do listy wyboru.
  /// Pies z nieczytelnym zapisem też jest na liście, żeby dało się go odzyskać.
  Dog? peek(String id) {
    if (id == activeId && AppStore.instance.ownerId == id && AppStore.instance.dog != null) {
      return AppStore.instance.dog;
    }
    final raw = _prefs?.getString(AppStore.keyForDog(id));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j['dog'] == null ? null : Dog.fromJson(Map<String, dynamic>.from(j['dog'] as Map));
    } catch (_) {
      final m = RegExp(r'"name"\s*:\s*"([^"\\]{1,60})"').firstMatch(raw);
      return Dog(name: m == null ? tr('Pies – dane do odzyskania') : tr('{0} – dane do odzyskania', [m.group(1)!]));
    }
  }

  List<(String, Dog)> get dogs => [
        for (final id in ids)
          if (peek(id) case final d?) (id, d),
      ];

  Future<void> switchTo(String id) => _ops.run(() async {
        await _waitPending();
        if (id == activeId) return;
        await _change(() {
          activeId = id;
          returnTo = null;
        });
        await reloadAll();
      });

  /// Zaczyna dodawanie nowego psa – aplikacja pokaże ekran powitalny i kreator.
  Future<void> startAdding() => _ops.run(() async {
        await _waitPending();
        final back = activeId;
        await _change(() {
          returnTo = back;
          activeId = 'd${DateTime.now().millisecondsSinceEpoch}';
        });
        await reloadAll();
      });

  /// Przerwanie dodawania – powrót do poprzedniego psa.
  Future<void> cancelAdding() => _ops.run(() async {
        await _waitPending();
        final back = returnTo ?? (ids.isNotEmpty ? ids.first : null);
        if (back == null) return;
        final gone = activeId;
        await _journal(gone);
        await _change(() {
          activeId = back;
          returnTo = null;
        });
        await _runCleanup();
        await reloadAll();
      });

  /// Usuwa wybranego psa razem z jego danymi, trasami GPS i załącznikami.
  ///
  /// Kolejność odporna na przerwanie: (1) dziennik sprzątania z listą plików,
  /// (2) usunięcie psa z listy, (3) usunięcie zapisów i plików, (4) wyczyszczenie
  /// dziennika. Po restarcie niedokończone sprzątanie jest kończone w [load].
  Future<void> deleteActive() => _ops.run(() async {
        await _waitPending();
        final id = activeId;
        await _journal(id);
        await _change(() {
          ids.remove(id);
          activeId = ids.isNotEmpty ? ids.first : mainId;
          returnTo = null;
        });
        await _runCleanup();
        await reloadAll();
      });

  /// Klucze zapisu psa (także kopie odzysku i szkice).
  static List<String> keysOf(SharedPreferences p, String id) {
    final s = suffixFor(id);
    final own = {for (final b in perDogKeys) '$b$s'};
    return [
      for (final k in p.getKeys())
        if (own.contains(k) || own.any((o) => k.startsWith('${SafePrefs.recoveryPrefix}$o|'))) k
    ];
  }

  /// Pliki należące wyłącznie do psa [id] (bez plików wskazywanych przez inne zapisy).
  static Set<String> filesOwnedBy(SharedPreferences p, String id) {
    final keys = keysOf(p, id).toSet();
    final mine = <String>{};
    for (final k in keys) {
      final v = p.get(k);
      if (v is String) mine.addAll(FileRefs.extract(v));
    }
    return mine.difference(FileRefs.referenced(p, exceptKeys: {...keys, _cleanupKey}));
  }

  List<Map<String, dynamic>> _readJournal(SharedPreferences p) {
    final raw = p.getString(_cleanupKey);
    if (raw == null) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  Set<String> _pendingCleanupIds(SharedPreferences p) => {for (final e in _readJournal(p)) e['dog'] as String};

  Future<void> _journal(String id) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    final j = _readJournal(p)..removeWhere((e) => e['dog'] == id);
    j.add({'dog': id, 'files': filesOwnedBy(p, id).toList()..sort()});
    await SafePrefs.setString(p, _cleanupKey, jsonEncode(j));
  }

  /// Dokańcza sprzątanie po usuniętych psach (bezpieczne przy powtórzeniu).
  Future<void> _runCleanup() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    final journal = _readJournal(p);
    if (journal.isEmpty) return;
    final left = <Map<String, dynamic>>[];
    for (final e in journal) {
      final id = e['dog'] as String;
      if (ids.contains(id)) continue; // pies jest na liście – nic nie usuwamy
      try {
        for (final k in keysOf(p, id)) {
          await SafePrefs.remove(p, k);
        }
        await GpsDrafts.discardForDog(id);
        final other = FileRefs.referenced(p, exceptKeys: {_cleanupKey});
        for (final f in [for (final x in (e['files'] as List? ?? [])) x as String]) {
          if (!other.contains(f)) await FileStore.delete(f);
        }
      } catch (err) {
        logError('Sprzątanie po psie', err);
        left.add(e);
      }
    }
    try {
      if (left.isEmpty) {
        await SafePrefs.remove(p, _cleanupKey);
      } else {
        await SafePrefs.setString(p, _cleanupKey, jsonEncode(left));
      }
    } catch (err) {
      logError('Dziennik sprzątania', err);
    }
  }

  /// Raz na uruchomienie: pliki po starszych wersjach bez żadnego właściciela.
  Future<int> sweepOrphanFiles() async {
    final p = await SharedPreferences.getInstance();
    return FileRefs.sweepOrphans(p, indexReadable: indexReadable, perDogBases: perDogKeys);
  }

  Future<void> reloadAll() async {
    await AppStore.instance.load();
    await NutritionStore.instance.load();
    await ModuleStore.instance.load();
    await HeatStore.instance.load();
    await GalleryStore.instance.load();
    await BreedingStore.instance.load();
    await GuideStore.instance.load();
    notifyListeners();
    await Notifications.instance.reschedule(AppStore.instance);
  }
}

/// Klucz zapisu dla aktualnie wybranego psa.
String dogKey(String base) => DogProfiles.instance.keyFor(base);

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../breeding/breeding_store.dart';
import '../gallery/gallery_store.dart';
import '../guides/guide_store.dart';
import '../heat/heat_store.dart';
import '../models.dart';
import '../modules/module_store.dart';
import '../notifications.dart';
import '../nutrition/nutrition_store.dart';
import '../store.dart';

/// Lista psów w aplikacji i to, który jest teraz wybrany.
///
/// Każdy pies ma własny komplet danych (trening, zdrowie, żywienie, cieczka,
/// hodowla, galeria, poradniki, moduły). Pierwszy pies (`main`) używa starych
/// kluczy zapisu, więc dane sprzed tej wersji zostają u niego bez przenoszenia.
/// Kolejne psy zapisują się pod kluczami z dopiskiem `@<id>`.
class DogProfiles extends ChangeNotifier {
  DogProfiles._();
  static final DogProfiles instance = DogProfiles._();

  static const _key = 'valkor_dogs_v1';
  static const mainId = 'main';

  /// Klucze wszystkich danych zależnych od psa.
  static const perDogKeys = [
    'k9coach_data_v1',
    'k9coach_nutrition_v1',
    'valkor_modules_v1',
    'valkor_heat_v1',
    'valkor_gallery_v1',
    'valkor_breeding_v1',
    'valkor_guides_v1',
  ];

  SharedPreferences? _prefs;
  List<String> ids = [];
  String activeId = mainId;

  /// Pies, do którego wracamy, gdy ktoś przerwie dodawanie nowego psa.
  String? returnTo;

  static String suffixFor(String id) => id == mainId ? '' : '@$id';
  String get suffix => suffixFor(activeId);
  String keyFor(String base) => '$base$suffix';

  bool get adding => !ids.contains(activeId);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        ids = [for (final e in (j['ids'] as List? ?? [])) e as String];
        activeId = j['active'] as String? ?? mainId;
        returnTo = j['returnTo'] as String?;
      } catch (e) {
        debugPrint('Psy: błąd odczytu $e');
      }
    } else if (_prefs!.getString('k9coach_data_v1') != null) {
      // Pierwsze uruchomienie po aktualizacji: obecny pies staje się pierwszym na liście.
      ids = [mainId];
      activeId = mainId;
      await _write();
    }
    if (ids.isNotEmpty && !ids.contains(activeId) && returnTo == null) activeId = ids.first;
  }

  Future<void> _write() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode({'ids': ids, 'active': activeId, 'returnTo': returnTo}));
  }

  /// Wywoływane po zapisaniu profilu psa – nowy pies trafia na listę.
  Future<void> registerActive() async {
    if (ids.contains(activeId)) return;
    ids.add(activeId);
    returnTo = null;
    await _write();
    notifyListeners();
  }

  /// Odczyt profilu dowolnego psa (bez przełączania), np. do listy wyboru.
  Dog? peek(String id) {
    if (id == activeId) return AppStore.instance.dog;
    final raw = _prefs?.getString('k9coach_data_v1${suffixFor(id)}');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j['dog'] == null ? null : Dog.fromJson(j['dog']);
    } catch (_) {
      return null;
    }
  }

  List<(String, Dog)> get dogs => [
        for (final id in ids)
          if (peek(id) case final d?) (id, d),
      ];

  Future<void> switchTo(String id) async {
    if (id == activeId) return;
    activeId = id;
    returnTo = null;
    await _write();
    await _reloadAll();
  }

  /// Zaczyna dodawanie nowego psa – aplikacja pokaże ekran powitalny i kreator.
  Future<void> startAdding() async {
    returnTo = activeId;
    activeId = 'd${DateTime.now().millisecondsSinceEpoch}';
    await _write();
    await _reloadAll();
  }

  /// Przerwanie dodawania – powrót do poprzedniego psa.
  Future<void> cancelAdding() async {
    final back = returnTo ?? (ids.isNotEmpty ? ids.first : null);
    if (back == null) return;
    await _clearKeys(activeId);
    activeId = back;
    returnTo = null;
    await _write();
    await _reloadAll();
  }

  /// Usuwa wybranego psa razem z jego danymi i przełącza na kolejnego.
  Future<void> deleteActive() async {
    final id = activeId;
    await AppStore.instance.resetAll();
    await _clearKeys(id);
    ids.remove(id);
    activeId = ids.isNotEmpty ? ids.first : mainId;
    returnTo = null;
    await _write();
    await _reloadAll();
  }

  Future<void> _clearKeys(String id) async {
    _prefs ??= await SharedPreferences.getInstance();
    for (final k in perDogKeys) {
      await _prefs!.remove('$k${suffixFor(id)}');
    }
  }

  Future<void> _reloadAll() async {
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

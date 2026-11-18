import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../build_config.dart';
import '../storage/dog_doc_guard.dart';
import '../storage/safe_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';

import '../models.dart';
import '../guides/guide_store.dart';
import '../guides/guides_data.dart';
import '../store.dart';
import 'modules.dart';

/// Skąd pochodzi Premium.
enum PremiumSource {
  /// Przełącznik testowy (aplikacja spoza Sklepu Play).
  test,

  /// Subskrypcja w Google Play.
  play,
}

/// Stan modułów: ręczne włączenia/wyłączenia i flaga Premium.
/// Zapisywane osobno od danych psa, więc stare dane zostają nietknięte.
class ModuleStore extends ChangeNotifier {
  ModuleStore._();
  static final ModuleStore instance = ModuleStore._();

  static const _key = 'valkor_modules_v1';
  // Premium dotyczy całej aplikacji (wszystkich psów), więc ma własny klucz.
  static const _premiumKey = 'valkor_premium_v1';
  SharedPreferences? _prefs;

  /// null = automatycznie wg profilu, true/false = ręcznie.
  final Map<AppModule, bool> overrides = {};

  /// Premium: subskrypcja Google Play albo przełącznik testowy (patrz Billing).
  bool _premium = false;

  /// Premium aktywne: w becie także testowo, w wersji produkcyjnej wyłącznie
  /// z potwierdzonego zakupu Google Play (stary przełącznik testowy nie działa).
  bool get premium => _premium && (isBetaBuild || premiumSource == PremiumSource.play);
  PremiumSource premiumSource = PremiumSource.test;

  final guard = DogDocGuard(_key, 'Moduły');

  static Map<AppModule, bool> _parse(String? raw) {
    final out = <AppModule, bool>{};
    if (raw == null) return out;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final o = (j['overrides'] as Map?) ?? {};
    for (final e in o.entries) {
      final m = AppModule.values.asNameMap()[e.key];
      if (m != null && e.value is bool) out[m] = e.value as bool;
    }
    return out;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    // Starsze wersje trzymały Premium razem z modułami pierwszego psa.
    final rawPremium = _prefs!.getString(_premiumKey) ?? _prefs!.getString(_key);
    if (rawPremium != null) {
      try {
        final j = jsonDecode(rawPremium) as Map<String, dynamic>;
        _premium = j['premium'] as bool? ?? false;
        premiumSource = PremiumSource.values.asNameMap()[j['premiumSource']] ?? PremiumSource.test;
      } catch (e) {
        logError('Premium: odczyt', e);
      }
    }
    var x = <AppModule, bool>{};
    await guard.load(_prefs!, DogProfiles.instance.activeId, (raw) => x = _parse(raw));
    overrides
      ..clear()
      ..addAll(x);
    notifyListeners();
  }

  Future<void> _savePremium() async {
    _prefs ??= await SharedPreferences.getInstance();
    await SafePrefs.setString(
        _prefs!, _premiumKey, jsonEncode({'premium': _premium, 'premiumSource': premiumSource.name}));
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    try {
      await guard.write(
          _prefs!,
          () => jsonEncode({
                'premium': _premium,
                'premiumSource': premiumSource.name,
                'overrides': {for (final e in overrides.entries) e.key.name: e.value},
              }),
          (last) => overrides
            ..clear()
            ..addAll(_parse(last)));
    } finally {
      notifyListeners();
    }
  }

  /// Czy moduł ma już dane użytkownika – wtedy nie chowamy go automatycznie.
  bool hasData(AppModule m) {
    final s = AppStore.instance;
    final guide = guides[m];
    if (guide != null) return guide.exercises.any((e) => GuideStore.instance.statusOf(e.id) > 0);
    bool trained(Discipline d) => s.trainings.any((t) => t.discipline == d);
    return switch (m) {
      AppModule.canicross => trained(Discipline.canicross),
      AppModule.bikejoring => trained(Discipline.bikejoring),
      AppModule.obedience => trained(Discipline.obedience),
      AppModule.bhvt => trained(Discipline.bhvt),
      AppModule.igp => trained(Discipline.igp),
      AppModule.tracking => trained(Discipline.nosework),
      AppModule.shows || AppModule.evaluations => s.shows.isNotEmpty,
      _ => false,
    };
  }

  bool isAuto(AppModule m) => !overrides.containsKey(m);

  bool autoFor(AppModule m, Dog dog) => m.autoEnabled(dog, premium: premium, hasData: hasData(m));

  bool isEnabled(AppModule m, [Dog? dog]) {
    final d = dog ?? AppStore.instance.dog;
    if (d == null) return false;
    if (!m.applicable(d, premium: premium)) return false;
    return overrides[m] ?? autoFor(m, d);
  }

  List<AppModule> enabled([Dog? dog]) => [for (final m in AppModule.values) if (isEnabled(m, dog)) m];

  Future<void> setEnabled(AppModule m, bool on) async {
    final d = AppStore.instance.dog;
    if (d != null && autoFor(m, d) == on) {
      overrides.remove(m); // zgodne z automatem – wracamy do trybu automatycznego
    } else {
      overrides[m] = on;
    }
    await _save();
  }

  Future<void> resetOverrides() async {
    overrides.clear();
    await _save();
  }

  Future<void> setPremium(bool on, {PremiumSource source = PremiumSource.test}) async {
    if (source == PremiumSource.test && !isBetaBuild) return; // brak trybu testowego w produkcji
    if (_premium == on && premiumSource == source) return;
    final old = (_premium, premiumSource);
    _premium = on;
    premiumSource = source;
    try {
      await _savePremium();
    } catch (e) {
      _premium = old.$1;
      premiumSource = old.$2;
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  SharedPreferences? _prefs;

  /// null = automatycznie wg profilu, true/false = ręcznie.
  final Map<AppModule, bool> overrides = {};

  /// Premium: subskrypcja Google Play albo przełącznik testowy (patrz Billing).
  bool premium = false;
  PremiumSource premiumSource = PremiumSource.test;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      premium = j['premium'] ?? false;
      premiumSource = PremiumSource.values.asNameMap()[j['premiumSource']] ?? PremiumSource.test;
      overrides.clear();
      final o = (j['overrides'] as Map?) ?? {};
      for (final e in o.entries) {
        final m = AppModule.values.asNameMap()[e.key];
        if (m != null && e.value is bool) overrides[m] = e.value as bool;
      }
    } catch (e) {
      debugPrint('Moduły: błąd odczytu $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
        _key,
        jsonEncode({
          'premium': premium,
          'premiumSource': premiumSource.name,
          'overrides': {for (final e in overrides.entries) e.key.name: e.value},
        }));
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
    if (premium == on && premiumSource == source) return;
    premium = on;
    premiumSource = source;
    await _save();
  }

  Future<void> reset() async {
    overrides.clear();
    // Opłaconej subskrypcji nie kasujemy razem z danymi psa.
    if (premiumSource != PremiumSource.play) premium = false;
    await _save();
  }
}

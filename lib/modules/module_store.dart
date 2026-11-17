import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../store.dart';
import 'modules.dart';

/// Stan modułów: ręczne włączenia/wyłączenia i flaga Premium.
/// Zapisywane osobno od danych psa, więc stare dane zostają nietknięte.
class ModuleStore extends ChangeNotifier {
  ModuleStore._();
  static final ModuleStore instance = ModuleStore._();

  static const _key = 'valkor_modules_v1';
  SharedPreferences? _prefs;

  /// null = automatycznie wg profilu, true/false = ręcznie.
  final Map<AppModule, bool> overrides = {};

  /// Premium (na razie lokalny przełącznik – brak systemu płatności).
  bool premium = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      premium = j['premium'] ?? false;
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
          'overrides': {for (final e in overrides.entries) e.key.name: e.value},
        }));
  }

  /// Czy moduł ma już dane użytkownika – wtedy nie chowamy go automatycznie.
  bool hasData(AppModule m) {
    final s = AppStore.instance;
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

  Future<void> setPremium(bool on) async {
    premium = on;
    await _save();
  }

  Future<void> reset() async {
    overrides.clear();
    premium = false;
    await _save();
  }
}

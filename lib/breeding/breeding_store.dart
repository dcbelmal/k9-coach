import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../notifications.dart';
import '../store.dart';
import 'breeding_logic.dart';
import 'breeding_models.dart';
import '../l10n/l10n.dart';

/// Moduł hodowlany (Premium) – dane zapisane osobno (klucz valkor_breeding_v1).
class BreedingStore extends ChangeNotifier {
  BreedingStore._();
  static final BreedingStore instance = BreedingStore._();

  static const _key = 'valkor_breeding_v1';
  SharedPreferences? _prefs;

  List<Mating> matings = [];
  bool remind = true;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      matings = [for (final e in (j['matings'] as List? ?? [])) Mating.fromJson(e)];
      remind = j['remind'] ?? true;
      _sort();
    } catch (e) {
      debugPrint('Hodowla: błąd odczytu $e');
    }
  }

  void _sort() => matings.sort((a, b) => b.first.compareTo(a.first));

  Future<void> _write() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode({'matings': matings.map((m) => m.toJson()).toList(), 'remind': remind}));
  }

  Future<void> _save() async {
    _sort();
    notifyListeners();
    await _write();
    await Notifications.instance.reschedule(AppStore.instance);
  }

  /// Trwająca ciąża (lub oczekiwanie na potwierdzenie) – najnowsza.
  Mating? get active {
    final now = DateTime.now();
    for (final m in matings) {
      if (PregnancyCalc.isActive(m, now)) return m;
    }
    return null;
  }

  List<Mating> get litters => [for (final m in matings) if (m.litter != null) m];

  Future<void> upsert(Mating m) async {
    matings.removeWhere((e) => e.id == m.id);
    matings.add(m);
    await _save();
  }

  Future<void> delete(Mating m) async {
    matings.removeWhere((e) => e.id == m.id);
    await _save();
  }

  Future<void> setStatus(Mating m, PregnancyStatus s) async {
    m.status = s;
    await _save();
  }

  /// Zapis po zmianach w miocie / szczeniętach (bez przeplanowania powiadomień).
  Future<void> touch() async {
    notifyListeners();
    await _write();
  }

  Future<void> setRemind(bool on) async {
    remind = on;
    await _save();
  }

  List<(DateTime, String, String)> notificationPlan() {
    if (!remind) return const [];
    final dog = AppStore.instance.dog;
    if (dog == null || !dog.female) return const [];
    if (!ModuleStore.instance.isEnabled(AppModule.breeding)) return const [];
    final m = active;
    if (m == null) return const [];
    final out = <(DateTime, String, String)>[];
    for (final ms in PregnancyCalc.milestones.skip(1)) {
      final d = PregnancyCalc.milestoneDate(m, ms);
      out.add((DateTime(d.year, d.month, d.day, 9), '${dog.name}: ${ms.title}', ms.text));
    }
    return out;
  }

  Future<void> reset() async {
    matings = [];
    remind = true;
    await _save();
  }

  /// Dane przykładowe: trwająca ciąża i poprzedni miot ze szczeniętami.
  Future<void> loadDemo() async {
    final today = dayOnly(DateTime.now());
    final m1 = today.subtract(const Duration(days: 34));
    final born = today.subtract(const Duration(days: 400));
    final litter = Litter(born: born, notes: tr('Poród naturalny, 6 h'), puppies: [
      for (final (i, p) in [
        (tr('Atos'), false, tr('płowy'), 410),
        (tr('Bora'), true, tr('płowa'), 380),
        (tr('Cezar'), false, tr('płowy'), 455),
        (tr('Dina'), true, tr('płowa z maską'), 360),
        (tr('Echo'), true, tr('płowa'), 395),
      ].indexed)
        Puppy(id: 'p$i', name: p.$1, female: p.$2, color: p.$3, weights: [
          for (var d = 0; d <= 14; d += 2) PuppyWeight(born.add(Duration(days: d)), (p.$4 * (1 + d * (0.105 - i * 0.004))).round()),
        ]),
    ]);
    matings = [
      Mating(
        id: 'm1',
        dates: [m1, m1.add(const Duration(days: 2))],
        partner: tr('Ares z Valkor Canis'),
        status: PregnancyStatus.confirmed,
        notes: tr('Progesteron 18 ng/ml w dniu krycia'),
      ),
      Mating(
        id: 'm0',
        dates: [born.subtract(const Duration(days: 63)), born.subtract(const Duration(days: 61))],
        partner: tr('Bruno Malinowy Las'),
        status: PregnancyStatus.whelped,
        litter: litter,
      ),
    ];
    _sort();
    notifyListeners();
    await _write();
  }
}

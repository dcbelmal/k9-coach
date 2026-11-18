import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';

import '../models.dart';
import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../notifications.dart';
import '../store.dart';
import 'heat_logic.dart';
import '../l10n/l10n.dart';

/// Moduł „Cykl i cieczka” – dane zapisane osobno (klucz valkor_heat_v1).
class HeatStore extends ChangeNotifier {
  HeatStore._();
  static final HeatStore instance = HeatStore._();

  static const _key = 'valkor_heat_v1';
  SharedPreferences? _prefs;

  List<HeatCycle> cycles = [];
  bool remind = true;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(dogKey(_key));
    cycles = [];
    remind = true;
    if (raw == null) {
      notifyListeners();
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      cycles = [for (final e in (j['cycles'] as List? ?? [])) HeatCycle.fromJson(e)];
      remind = j['remind'] ?? true;
      _sort();
    } catch (e) {
      debugPrint('Cieczka: błąd odczytu $e');
    }
    notifyListeners();
  }

  void _sort() => cycles.sort((a, b) => b.start.compareTo(a.start));

  Future<void> _save() async {
    _sort();
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
        dogKey(_key), jsonEncode({'cycles': cycles.map((c) => c.toJson()).toList(), 'remind': remind}));
    await Notifications.instance.reschedule(AppStore.instance);
  }

  HeatStatus get status => HeatLogic.status(cycles, DateTime.now());

  Future<void> upsert(HeatCycle c) async {
    cycles.removeWhere((e) => e.id == c.id);
    cycles.add(c);
    await _save();
  }

  Future<void> delete(HeatCycle c) async {
    cycles.removeWhere((e) => e.id == c.id);
    await _save();
  }

  Future<void> startToday() => upsert(HeatCycle(id: newId(), start: dayOnly(DateTime.now())));

  Future<void> setRemind(bool on) async {
    remind = on;
    await _save();
  }

  /// Przypomnienia do wspólnego planu powiadomień.
  List<(DateTime, String, String)> notificationPlan() {
    if (!remind || cycles.isEmpty) return const [];
    if (!ModuleStore.instance.isEnabled(AppModule.heat)) return const [];
    final name = AppStore.instance.dog?.name ?? tr('Suka');
    final st = status;
    final out = <(DateTime, String, String)>[];
    DateTime at(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);
    final next = st.nextStart;
    if (next != null) {
      out.add((at(next.subtract(const Duration(days: 7)), 9), tr('Za ok. tydzień cieczka'),
          tr('{0}: przewidywany początek {1}.{2}. Obserwuj sukę.', [name, next.day, next.month.toString().padLeft(2, '0')])));
      out.add((at(next, 9), tr('Spodziewana cieczka'), tr('{0}: dziś przewidywany początek. Zapisz, gdy się zacznie.', [name])));
    }
    final cur = st.current;
    if (cur != null) {
      final s = dayOnly(cur.start);
      out.add((at(s.add(const Duration(days: HeatLogic.proestrusDays)), 8), tr('Zaczynają się dni płodne'),
          tr('{0}: ok. {1}. dzień cieczki. Pilnuj na spacerach.', [name, HeatLogic.proestrusDays + 1])));
      if (cur.end == null) {
        out.add((at(s.add(const Duration(days: HeatLogic.typicalLength + 1)), 18), tr('Czy cieczka się skończyła?'),
            tr('{0}: zapisz koniec cieczki, żeby prognoza była dokładniejsza.', [name])));
      }
    }
    return out;
  }

  Future<void> reset() async {
    cycles = [];
    remind = true;
    await _save();
  }

  Future<void> loadDemo() async {
    final today = dayOnly(DateTime.now());
    final s1 = today.subtract(const Duration(days: 178));
    cycles = [
      HeatCycle(
          id: 'hc1',
          start: s1.subtract(const Duration(days: 185)),
          end: s1.subtract(const Duration(days: 165)),
          notes: tr('Pierwsza cieczka')),
      HeatCycle(id: 'hc2', start: s1, end: s1.add(const Duration(days: 20))),
    ];
    _sort();
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
        dogKey(_key), jsonEncode({'cycles': cycles.map((c) => c.toJson()).toList(), 'remind': remind}));
  }
}

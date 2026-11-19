import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/dog_doc_guard.dart';
import '../storage/safe_prefs.dart';
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

  List<dynamic> _bad = [];
  final guard = DogDocGuard(_key, 'Cykl i cieczka');

  static (List<HeatCycle>, bool, List<dynamic>) _parse(String? raw) {
    if (raw == null) return ([], true, []);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final (ok, bad) = readList(j['cycles'], HeatCycle.fromJson);
    return (ok, j['remind'] as bool? ?? true, bad);
  }

  void _apply((List<HeatCycle>, bool, List<dynamic>) x) {
    cycles = x.$1;
    remind = x.$2;
    _bad = x.$3;
    _sort();
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    var x = _parse(null);
    await guard.load(_prefs!, DogProfiles.instance.activeId, (raw) => x = _parse(raw));
    _apply(x);
    notifyListeners();
  }

  void _sort() => cycles.sort((a, b) => b.start.compareTo(a.start));

  Future<void> _save({bool reschedule = true}) async {
    _sort();
    _prefs ??= await SharedPreferences.getInstance();
    try {
      await guard.write(
          _prefs!,
          () => jsonEncode({'cycles': [...cycles.map((c) => c.toJson()), ..._bad], 'remind': remind}),
          (last) => _apply(_parse(last)));
    } finally {
      notifyListeners();
    }
    if (reschedule) await Notifications.instance.reschedule(AppStore.instance);
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
      if (cur.ovulation == null) {
        out.add((at(s.add(const Duration(days: HeatLogic.testFromDay - 1)), 8), tr('Cieczka: planujesz krycie?'),
            tr('{0}: jeśli planujesz krycie, ustal z lekarzem weterynarii termin badania progesteronu. Suka może być płodna przez całą cieczkę – pilnuj jej na spacerach.', [name])));
      }
      if (cur.end == null) {
        out.add((at(s.add(Duration(days: st.typicalLengthDays + 1)), 18), tr('Czy cieczka się skończyła?'),
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
    await _save(reschedule: false);
  }
}

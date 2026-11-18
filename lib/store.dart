import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' show Icons, Color;
import 'package:shared_preferences/shared_preferences.dart';

import 'champ_rules.dart';
import 'dogs/dog_profiles.dart';
import 'files/file_store.dart';
import 'gps/demo_track.dart';
import 'heat/heat_store.dart';
import 'models.dart';
import 'models_ext.dart';
import 'notifications.dart';
import 'nutrition/nutrition_store.dart';
import 'storage/safe_prefs.dart';
import 'l10n/l10n.dart';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime startOfWeek(DateTime d) =>
    dayOnly(d).subtract(Duration(days: d.weekday - 1));

/// Stan gotowości psa na podstawie stosunku obciążenia ostrego do przewlekłego (ACWR).
class Readiness {
  final int score; // 0-100
  final double ratio;
  final String label;
  final String advice;
  final int level; // 0 = za mało, 1 = optymalnie, 2 = uwaga, 3 = ryzyko
  const Readiness(this.score, this.ratio, this.label, this.advice, this.level);
}

class PeriodStats {
  final int count;
  final double km;
  final int minutes;
  const PeriodStats(this.count, this.km, this.minutes);
}

/// Komplet danych jednego psa w postaci zapisu (klucz k9coach_data_v1[@id]).
///
/// Odczyt jest ostrożny: wpis, którego nie da się odczytać (np. z nieznaną
/// dyscypliną), nie jest kasowany – trafia do [unreadable] i przy kolejnym
/// zapisie wraca do pliku bez zmian. Pola nieznane tej wersji trafiają do [extra].
class DogDataDoc {
  /// Wersja schematu. 1 = zapisy bez pola `schema` (do 0.11.0), 2 = od 0.12.0.
  static const schemaVersion = 2;
  static const sections = ['weights', 'health', 'trainings', 'events', 'shows', 'documents', 'gear', 'goals'];

  Dog? dog;
  List<WeightEntry> weights = [];
  List<HealthRecord> health = [];
  List<TrainingSession> trainings = [];
  List<CalendarEvent> events = [];
  List<ShowEntry> shows = [];
  List<DogDocument> documents = [];
  List<GearItem> gear = [];
  List<Goal> goals = [];
  final Map<String, List<dynamic>> unreadable = {};
  final Map<String, dynamic> extra = {};

  int get unreadableCount => unreadable.values.fold(0, (a, l) => a + l.length);

  /// Rzuca wyjątek, gdy całego zapisu nie da się bezpiecznie użyć
  /// (uszkodzony JSON, nowszy schemat, nieczytelny profil psa).
  static DogDataDoc decode(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map) throw const FormatException('root');
    final m = Map<String, dynamic>.from(j);
    final schema = m['schema'];
    if (schema != null && (schema is! int || schema > schemaVersion)) {
      throw const FormatException('schema');
    }
    final d = DogDataDoc();
    d.dog = m['dog'] == null ? null : Dog.fromJson(Map<String, dynamic>.from(m['dog'] as Map));
    void sec<T>(String name, List<T> into, T Function(Map<String, dynamic>) parse) {
      final (ok, bad) = readList(m[name], parse);
      into.addAll(ok);
      if (bad.isNotEmpty) d.unreadable[name] = bad;
    }

    sec('weights', d.weights, WeightEntry.fromJson);
    sec('health', d.health, HealthRecord.fromJson);
    sec('trainings', d.trainings, TrainingSession.fromJson);
    sec('events', d.events, CalendarEvent.fromJson);
    sec('shows', d.shows, ShowEntry.fromJson);
    sec('documents', d.documents, DogDocument.fromJson);
    sec('gear', d.gear, GearItem.fromJson);
    sec('goals', d.goals, Goal.fromJson);
    for (final e in m.entries) {
      if (e.key != 'dog' && e.key != 'schema' && !sections.contains(e.key)) d.extra[e.key] = e.value;
    }
    return d;
  }

  Map<String, dynamic> toJson() {
    List<dynamic> sec(String name, List<dynamic> items) =>
        [for (final e in items) e.toJson(), ...?unreadable[name]];
    return {
      ...extra,
      'schema': schemaVersion,
      'dog': dog?.toJson(),
      'weights': sec('weights', weights),
      'health': sec('health', health),
      'trainings': sec('trainings', trainings),
      'events': sec('events', events),
      'shows': sec('shows', shows),
      'documents': sec('documents', documents),
      'gear': sec('gear', gear),
      'goals': sec('goals', goals),
    };
  }
}

/// Cały stan aplikacji, zapisywany lokalnie na telefonie.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const baseKey = 'k9coach_data_v1';
  static const _key = baseKey;
  late SharedPreferences _prefs;

  Dog? dog;
  List<WeightEntry> weights = [];
  List<HealthRecord> health = [];
  List<TrainingSession> trainings = [];
  List<CalendarEvent> events = [];
  List<ShowEntry> shows = [];
  List<DogDocument> documents = [];
  List<GearItem> gear = [];
  List<Goal> goals = [];

  /// Pies, którego dane są teraz w pamięci.
  String get ownerId => _owner;
  String _owner = DogProfiles.mainId;

  /// true = danych tego psa nie dało się odczytać, zapis jest zablokowany.
  bool locked = false;

  /// Liczba wpisów zachowanych bez odczytu (wracają do zapisu bez zmian).
  int get unreadableCount => _doc.unreadableCount;

  DogDataDoc _doc = DogDataDoc();
  String? _lastGoodRaw;
  final _queue = SerialQueue();

  static String keyForDog(String id) => '$_key${DogProfiles.suffixFor(id)}';

  Future<void> load() => _queue.run(_load);

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final owner = DogProfiles.instance.activeId;
    final key = keyForDog(owner);
    final raw = _prefs.getString(key);
    // Najpierw odczyt do modelu tymczasowego – stan aplikacji podmieniamy dopiero potem.
    var doc = DogDataDoc();
    var lock = false;
    String? reason;
    if (raw != null) {
      try {
        doc = DogDataDoc.decode(raw);
      } catch (e) {
        logError('Odczyt danych psa', e);
        lock = true;
        reason = e.runtimeType.toString();
      }
    }
    String? backup;
    if (raw != null && (lock || doc.unreadableCount > 0)) {
      backup = await SafePrefs.preserve(_prefs, key, raw);
    }
    _owner = owner;
    locked = lock;
    _lastGoodRaw = lock ? null : raw;
    _apply(doc);
    if (lock || doc.unreadableCount > 0) {
      DataHealth.instance.report(StoreIssue(
          key: key,
          store: tr('Profil, treningi i zdrowie'),
          locked: lock,
          unreadable: doc.unreadableCount,
          backupKey: backup,
          reason: reason ?? ''));
    } else {
      DataHealth.instance.clear(key);
    }
    notifyListeners();
  }

  void _apply(DogDataDoc d) {
    _doc = d;
    dog = d.dog;
    weights = d.weights;
    health = d.health;
    trainings = d.trainings;
    events = d.events;
    shows = d.shows;
    documents = d.documents;
    gear = d.gear;
    goals = d.goals;
  }

  DogDataDoc _snapshot() => _doc
    ..dog = dog
    ..weights = weights
    ..health = health
    ..trainings = trainings
    ..events = events
    ..shows = shows
    ..documents = documents
    ..gear = gear
    ..goals = goals;

  void _restore() {
    var d = DogDataDoc();
    if (!locked && _lastGoodRaw != null) {
      try {
        d = DogDataDoc.decode(_lastGoodRaw!);
      } catch (_) {}
    }
    _apply(d);
  }

  /// Zmiana + trwały zapis jako jedna operacja. Stan w pamięci zmienia się
  /// na stałe dopiero po potwierdzonym zapisie; przy błędzie wraca poprzedni.
  Future<void> _commit(void Function() change) => _queue.run(() async {
        if (locked) throw StorageLockedException(keyForDog(_owner));
        change();
        _sort();
        final encoded = jsonEncode(_snapshot().toJson());
        try {
          await SafePrefs.setString(_prefs, keyForDog(_owner), encoded);
        } catch (e) {
          _restore();
          notifyListeners();
          rethrow;
        }
        _lastGoodRaw = encoded;
        notifyListeners();
        // Indeks psów dopiero po zapisie profilu: przerwanie między krokami
        // naprawia DogProfiles.load (pies z danymi wraca na listę).
        if (dog != null && DogProfiles.instance.activeId == _owner) await DogProfiles.instance.registerActive();
        await Notifications.instance.reschedule(this);
      });

  Future<void> _save() => _commit(() {});

  /// Zmiana danych psa, który nie jest teraz w pamięci (np. trening GPS
  /// rozpoczęty dla psa A i kończony po przełączeniu na B).
  Future<void> _commitFor(String dogId, void Function(DogDataDoc d) change) => _queue.run(() async {
        if (dogId == _owner) {
          if (locked) throw StorageLockedException(keyForDog(_owner));
          final d = _snapshot();
          change(d);
          _apply(d);
          _sort();
          final encoded = jsonEncode(_snapshot().toJson());
          try {
            await SafePrefs.setString(_prefs, keyForDog(_owner), encoded);
          } catch (e) {
            _restore();
            notifyListeners();
            rethrow;
          }
          _lastGoodRaw = encoded;
          notifyListeners();
          await Notifications.instance.reschedule(this);
          return;
        }
        final key = keyForDog(dogId);
        final raw = _prefs.getString(key);
        if (raw == null) throw StorageLockedException(key);
        final DogDataDoc d;
        try {
          d = DogDataDoc.decode(raw);
        } catch (_) {
          throw StorageLockedException(key);
        }
        change(d);
        await SafePrefs.setString(_prefs, key, jsonEncode(d.toJson()));
      });

  /// Trening zapisany zawsze u wskazanego psa (bezpieczne przy ponowieniu – upsert po ID).
  Future<void> upsertTrainingFor(String dogId, TrainingSession t) => _commitFor(dogId, (d) {
        d.trainings.removeWhere((e) => e.id == t.id);
        d.trainings.add(t);
      });

  /// Czy pies ma już trening o tym ID (szukane w zapisie, także innego psa).
  bool hasTrainingFor(String dogId, String id) {
    if (dogId == _owner) return trainings.any((t) => t.id == id);
    final raw = _prefs.getString(keyForDog(dogId));
    if (raw == null) return false;
    try {
      return DogDataDoc.decode(raw).trainings.any((t) => t.id == id);
    } catch (_) {
      return false;
    }
  }

  /// Odzysk: zapis tylko poprawnie odczytanych wpisów (oryginał zostaje w kopii).
  /// Zwraca false, gdy nie udało się zachować kopii oryginału.
  Future<bool> salvage() => _queue.run(() async {
        final key = keyForDog(_owner);
        final raw = _prefs.getString(key);
        if (raw != null && await SafePrefs.preserve(_prefs, key, raw) == null) return false;
        final d = raw == null ? DogDataDoc() : salvageDoc(raw);
        await SafePrefs.setString(_prefs, key, jsonEncode(d.toJson()));
        locked = false;
        _lastGoodRaw = jsonEncode(d.toJson());
        _apply(d);
        DataHealth.instance.clear(key);
        notifyListeners();
        return true;
      });

  /// Wydobywa z uszkodzonego zapisu wszystko, co da się odczytać.
  static DogDataDoc salvageDoc(String raw) {
    try {
      return DogDataDoc.decode(raw);
    } catch (_) {}
    final d = DogDataDoc();
    dynamic j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      return d;
    }
    if (j is! Map) return d;
    try {
      if (j['dog'] is Map) d.dog = Dog.fromJson(Map<String, dynamic>.from(j['dog'] as Map));
    } catch (_) {}
    List<T> ok<T>(String name, T Function(Map<String, dynamic>) parse) {
      try {
        final (list, bad) = readList(j[name], parse);
        if (bad.isNotEmpty) d.unreadable[name] = bad;
        return list;
      } catch (_) {
        return [];
      }
    }

    d.weights = ok('weights', WeightEntry.fromJson);
    d.health = ok('health', HealthRecord.fromJson);
    d.trainings = ok('trainings', TrainingSession.fromJson);
    d.events = ok('events', CalendarEvent.fromJson);
    d.shows = ok('shows', ShowEntry.fromJson);
    d.documents = ok('documents', DogDocument.fromJson);
    d.gear = ok('gear', GearItem.fromJson);
    d.goals = ok('goals', Goal.fromJson);
    return d;
  }

  void _sort() {
    weights.sort((a, b) => a.date.compareTo(b.date));
    health.sort((a, b) => b.date.compareTo(a.date));
    trainings.sort((a, b) => b.date.compareTo(a.date));
    events.sort((a, b) => a.date.compareTo(b.date));
    shows.sort((a, b) => b.date.compareTo(a.date));
    documents.sort((a, b) => a.type.index.compareTo(b.type.index));
    goals.sort((a, b) => (a.done ? 1 : 0).compareTo(b.done ? 1 : 0));
  }

  // --- Pies -----------------------------------------------------------------

  Future<void> saveDog(Dog d) => _commit(() {
        final oldWeight = dog?.weightKg;
        dog = d;
        if (d.weightKg != null && d.weightKg != oldWeight) {
          final today = dayOnly(DateTime.now());
          weights.removeWhere((w) => sameDay(w.date, today));
          weights.add(WeightEntry(id: newId(), date: today, kg: d.weightKg!));
        }
      });

  Future<void> addWeight(WeightEntry w) => _commit(() {
        weights.removeWhere((e) => sameDay(e.date, w.date));
        weights.add(w);
        _sort();
        if (dog != null && weights.isNotEmpty) dog!.weightKg = weights.last.kg;
      });

  Future<void> deleteWeight(WeightEntry w) => _commit(() {
        weights.removeWhere((e) => e.id == w.id);
        if (dog != null && weights.isNotEmpty) dog!.weightKg = weights.last.kg;
      });

  /// Usuwa wybranego psa razem z jego plikami (patrz DogProfiles.deleteActive).
  Future<void> resetAll() => DogProfiles.instance.deleteActive();

  // --- Zdrowie --------------------------------------------------------------

  Future<void> upsertHealth(HealthRecord r) => _commit(() {
        health.removeWhere((e) => e.id == r.id);
        health.add(r);
      });

  Future<void> deleteHealth(HealthRecord r) => _commit(() {
        health.removeWhere((e) => e.id == r.id);
      });

  /// Najnowszy wpis dla kategorii (decyduje o kolejnym terminie).
  HealthRecord? latestFor(HealthCategory c) {
    final list = health.where((h) => h.category == c).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.isEmpty ? null : list.first;
  }

  /// Aktualne terminy: dla każdej kategorii i tytułu bierzemy najnowszy wpis.
  List<HealthRecord> get dueItems {
    final latest = <String, HealthRecord>{};
    for (final h in health) {
      if (h.nextDue == null) continue;
      final k = '${h.category.name}|${h.title.toLowerCase().trim()}';
      if (!latest.containsKey(k) || latest[k]!.date.isBefore(h.date)) latest[k] = h;
    }
    final list = latest.values.toList()..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
    return list;
  }

  // --- Trening --------------------------------------------------------------

  Future<void> upsertTraining(TrainingSession t) => _commit(() {
        trainings.removeWhere((e) => e.id == t.id);
        trainings.add(t);
      });

  /// Plik trasy usuwamy dopiero po zapisaniu zmiany (gdy zapis się nie uda, trasa zostaje).
  Future<void> deleteTraining(TrainingSession t) async {
    await _commit(() => trainings.removeWhere((e) => e.id == t.id));
    if (t.trackRef != null) await FileStore.deleteIfUnreferenced(t.trackRef!);
  }

  Iterable<TrainingSession> get doneTrainings => trainings.where((t) => t.done);

  PeriodStats statsBetween(DateTime from, DateTime to) {
    var c = 0, m = 0;
    var km = 0.0;
    for (final t in doneTrainings) {
      if (!t.date.isBefore(from) && t.date.isBefore(to)) {
        c++;
        m += t.durationMin;
        km += t.distanceKm ?? 0;
      }
    }
    return PeriodStats(c, km, m);
  }

  PeriodStats get thisWeek {
    final s = startOfWeek(DateTime.now());
    return statsBetween(s, s.add(const Duration(days: 7)));
  }

  double _loadBetween(DateTime from, DateTime to) => doneTrainings
      .where((t) => !t.date.isBefore(from) && t.date.isBefore(to))
      .fold(0.0, (a, t) => a + t.load);

  Readiness get readiness {
    final now = DateTime.now();
    final end = dayOnly(now).add(const Duration(days: 1));
    final acute = _loadBetween(end.subtract(const Duration(days: 7)), end);
    final chronic = _loadBetween(end.subtract(const Duration(days: 28)), end) / 4;
    if (chronic < 1 && acute < 1) {
      return Readiness(50, 0, tr('Brak danych'),
          tr('Dodaj kilka treningów, a policzę formę i ryzyko przetrenowania.'), 0);
    }
    final ratio = chronic < 1 ? 2.0 : acute / chronic;
    // Wynik: 100 przy ratio 1.05, spada w obie strony.
    final score = (100 - (ratio - 1.05).abs() * 90).clamp(5, 100).round();
    if (ratio < 0.8) {
      return Readiness(score, ratio, tr('Wypoczęty'),
          tr('Obciążenie spadło. Pies jest gotowy na mocniejszy trening.'), 0);
    } else if (ratio <= 1.3) {
      return Readiness(score, ratio, tr('Optymalna forma'),
          tr('Obciążenie w bezpiecznym zakresie. Kontynuuj plan.'), 1);
    } else if (ratio <= 1.5) {
      return Readiness(score, ratio, tr('Uwaga'),
          tr('Obciążenie rośnie szybko. Zaplanuj lżejszy dzień lub regenerację.'), 2);
    }
    return Readiness(score, ratio, tr('Ryzyko przetrenowania'),
        tr('Ten tydzień jest dużo cięższy niż zwykle. Zalecany dzień regeneracji.'), 3);
  }

  // --- Kalendarz -----------------------------------------------------------

  Future<void> upsertEvent(CalendarEvent e) => _commit(() {
        events.removeWhere((x) => x.id == e.id);
        events.add(e);
      });

  Future<void> deleteEvent(CalendarEvent e) => _commit(() {
        events.removeWhere((x) => x.id == e.id);
      });

  List<AgendaItem> agendaFor(DateTime day) =>
      agendaBetween(dayOnly(day), dayOnly(day).add(const Duration(days: 1)));

  List<AgendaItem> agendaBetween(DateTime from, DateTime to) {
    bool inRange(DateTime d) => !d.isBefore(from) && d.isBefore(to);
    final items = <AgendaItem>[
      for (final t in trainings)
        if (inRange(t.date))
          AgendaItem(
              date: t.date,
              title: tr('Trening {0}', [t.discipline.label]),
              subtitle: t.done ? tr('Wykonany') : tr('Zaplanowany'),
              icon: t.discipline.icon,
              color: t.discipline.color,
              source: t),
      for (final h in dueItems)
        if (inRange(h.nextDue!))
          AgendaItem(
              date: h.nextDue!,
              title: h.title,
              subtitle: h.category.label,
              icon: h.category.icon,
              color: h.category.color,
              source: h),
      for (final sh in shows)
        if (sh.status != ShowStatus.cancelled && inRange(sh.date))
          AgendaItem(
              date: sh.date,
              title: sh.name,
              subtitle: tr('Wystawa · {0}', [sh.status.label]),
              icon: Icons.emoji_events_rounded,
              color: const Color(0xFFFFB020),
              source: sh),
      for (final sh in shows)
        if (sh.entryDeadline != null &&
            (sh.status == ShowStatus.planned) &&
            inRange(sh.entryDeadline!))
          AgendaItem(
              date: sh.entryDeadline!,
              title: tr('Zgłoszenie: {0}', [sh.name]),
              subtitle: tr('Termin zgłoszeń'),
              icon: Icons.assignment_late_rounded,
              color: const Color(0xFF5E8BFF),
              source: sh),
      for (final d in documents)
        if (d.expires != null && inRange(d.expires!))
          AgendaItem(
              date: d.expires!,
              title: tr('Ważność: {0}', [d.title]),
              subtitle: d.type.label,
              icon: d.type.icon,
              color: const Color(0xFFFF453A),
              source: d),
      for (final g in gear)
        if (!g.retired && g.replaceDate != null && inRange(g.replaceDate!))
          AgendaItem(
              date: g.replaceDate!,
              title: tr('Wymiana: {0}', [g.name]),
              subtitle: tr('Sprzęt'),
              icon: g.category.icon,
              color: const Color(0xFF30B0C7),
              source: g),
      for (final e in events)
        if (inRange(e.date))
          AgendaItem(
              date: e.date,
              title: e.title,
              subtitle: e.type.label,
              icon: e.type.icon,
              color: e.type.color,
              source: e),
    ];
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  List<AgendaItem> upcoming({int days = 60, int limit = 4}) {
    final now = DateTime.now();
    return agendaBetween(now, now.add(Duration(days: days)))
        .where((i) => !(i.source is TrainingSession && (i.source as TrainingSession).done))
        .take(limit)
        .toList();
  }

  // --- Wystawy, dokumenty, sprzęt, cele ------------------------------------

  Future<void> upsertShow(ShowEntry e) => _commit(() {
        shows.removeWhere((x) => x.id == e.id);
        shows.add(e);
      });

  Future<void> deleteShow(ShowEntry e) => _commit(() {
        shows.removeWhere((x) => x.id == e.id);
      });

  Future<void> upsertDocument(DogDocument e) => _commit(() {
        documents.removeWhere((x) => x.id == e.id);
        documents.add(e);
      });

  Future<void> deleteDocument(DogDocument e) async {
    await _commit(() => documents.removeWhere((x) => x.id == e.id));
    for (final i in e.images) {
      await FileStore.deleteIfUnreferenced(i);
    }
  }

  Future<void> upsertGear(GearItem e) => _commit(() {
        gear.removeWhere((x) => x.id == e.id);
        gear.add(e);
      });

  Future<void> deleteGear(GearItem e) async {
    await _commit(() => gear.removeWhere((x) => x.id == e.id));
    if (e.photo != null) await FileStore.deleteIfUnreferenced(e.photo!);
  }

  Future<void> upsertGoal(Goal e) => _commit(() {
        goals.removeWhere((x) => x.id == e.id);
        goals.add(e);
      });

  Future<void> deleteGoal(Goal e) => _commit(() {
        goals.removeWhere((x) => x.id == e.id);
      });

  bool get workingTrialPassed => goals.any((g) =>
      g.type == GoalType.exam && g.done && RegExp(r'IGP|IPO|FH|HWT', caseSensitive: false).hasMatch(g.title));

  ChampStatus champStatus(Championship c) {
    bool? pl;
    if (c == Championship.grand) {
      pl = champStatus(Championship.pl).achieved ||
          goals.any((g) => g.championship == Championship.pl && g.done);
    }
    return evaluate(c, shows,
        workingTrialBreed: isWorkingTrialBreed(dog), workingTrialPassed: workingTrialPassed, plChampion: pl);
  }

  /// Liczba zdobytych tytułów danego typu.
  int titleCount(ShowTitle t) => shows.where((s) => s.titles.contains(t)).length;

  /// Kilometry przebiegnięte w sprzęcie (treningi z wybranych dyscyplin od daty zakupu).
  double gearKm(GearItem g) => doneTrainings
      .where((t) =>
          g.disciplines.contains(t.discipline) &&
          (g.purchased == null || !t.date.isBefore(g.purchased!)))
      .fold(0.0, (a, t) => a + (t.distanceKm ?? 0));

  /// Zużycie sprzętu 0..1 (większe z: kilometry, czas).
  double gearWear(GearItem g) {
    var w = 0.0;
    if (g.maxKm != null && g.maxKm! > 0) w = gearKm(g) / g.maxKm!;
    final r = g.replaceDate;
    if (r != null && g.purchased != null) {
      final total = r.difference(g.purchased!).inDays;
      if (total > 0) {
        final used = DateTime.now().difference(g.purchased!).inDays / total;
        if (used > w) w = used;
      }
    }
    return w.clamp(0, 1.5).toDouble();
  }

  double _weightAt(DateTime d) {
    if (weights.isEmpty) return dog?.weightKg ?? 0;
    WeightEntry best = weights.first;
    for (final w in weights) {
      if ((w.date.difference(d).inDays).abs() < (best.date.difference(d).inDays).abs()) best = w;
    }
    return best.kg;
  }

  /// Postęp celu 0..1 oraz opis (np. "684 / 1000 km").
  (double, String) goalProgress(Goal g) {
    switch (g.type) {
      case GoalType.km:
        final to = g.deadline == null ? DateTime.now().add(const Duration(days: 1)) : g.deadline!.add(const Duration(days: 1));
        final km = statsBetween(g.start, to).km;
        final t = g.target ?? 0;
        return (t <= 0 ? 0 : km / t, '${km.toStringAsFixed(0)} / ${t.toStringAsFixed(0)} km');
      case GoalType.weight:
        final cur = dog?.weightKg ?? _weightAt(DateTime.now());
        final t = g.target ?? cur;
        final st = g.startValue ?? _weightAt(g.start);
        final txt = '${cur.toStringAsFixed(1).replaceAll('.', ',')} / ${t.toStringAsFixed(1).replaceAll('.', ',')} kg';
        if ((st - t).abs() < 0.05) return ((cur - t).abs() < 0.3 ? 1 : 0.5, txt);
        return (((st - cur) / (st - t)).clamp(0, 1).toDouble(), txt);
      case GoalType.title:
        final c = g.championship;
        if (c == null) return (g.done ? 1 : g.manualProgress, g.done ? 'Zdobyty' : 'W trakcie');
        final st = champStatus(c);
        return (g.done || st.achieved ? 1 : st.progress, g.done || st.achieved ? 'Spełnione wymagania · ${st.summary}' : st.summary);
      case GoalType.exam:
      case GoalType.custom:
        if (g.done) {
          return (1, g.doneDate == null ? 'Zaliczone' : 'Zaliczone: ${g.doneDate!.month.toString().padLeft(2, '0')}.${g.doneDate!.year}');
        }
        return (g.manualProgress, 'Przygotowanie ${(g.manualProgress * 100).round()}%');
    }
  }

  // --- Dane przykładowe ----------------------------------------------------

  Future<void> loadDemo() async {
    final rnd = Random(7);
    final now = DateTime.now();
    final today = dayOnly(now);
    dog = Dog(
      name: tr('Gamora'),
      breed: tr('Owczarek belgijski Malinois'),
      female: true,
      birthDate: DateTime(now.year - 1, now.month - 6, 7),
      weightKg: 20.5,
      heightCm: 54,
      bcs: 4,
      chip: '616093901234567',
      pedigree: tr('ZKwP-12345'),
      targetWeightKg: 22,
      weeklyKmGoal: 35,
      fciGroup: 1,
      breedId: 'malinois',
      activity: DogActivity.veryHigh,
      purpose: DogPurpose.sport,
    );
    try {
      final bytes = await rootBundle.load('assets/demo_gamora.jpg');
      dog!.photoBase64 = base64Encode(bytes.buffer.asUint8List());
    } catch (_) {}
    weights = [
      for (var i = 0; i < 10; i++)
        WeightEntry(
            id: newId() + i.toString(),
            date: today.subtract(Duration(days: (9 - i) * 21)),
            kg: double.parse((17.2 + i * 0.37 + rnd.nextDouble() * 0.3).toStringAsFixed(1)))
    ];
    weights.last.kg = 20.5;

    health = [
      HealthRecord(
          id: 'h1',
          category: HealthCategory.vaccination,
          title: tr('Szczepienie przeciw wściekliźnie'),
          date: today.subtract(const Duration(days: 355)),
          nextDue: today.add(const Duration(days: 10))),
      HealthRecord(
          id: 'h2',
          category: HealthCategory.vaccination,
          title: tr('DHPPi + L4'),
          date: today.subtract(const Duration(days: 120)),
          nextDue: today.add(const Duration(days: 245))),
      HealthRecord(
          id: 'h3',
          category: HealthCategory.deworming,
          title: tr('Milbemax'),
          date: today.subtract(const Duration(days: 40)),
          nextDue: today.add(const Duration(days: 50))),
      HealthRecord(
          id: 'h4',
          category: HealthCategory.ticks,
          title: tr('Bravecto'),
          date: today.subtract(const Duration(days: 70)),
          nextDue: today.add(const Duration(days: 20))),
      HealthRecord(
          id: 'h5',
          category: HealthCategory.tests,
          title: tr('HD/ED wstępne'),
          date: today.subtract(const Duration(days: 30)),
          notes: tr('HD A, ED 0')),
      HealthRecord(
          id: 'h6',
          category: HealthCategory.vet,
          title: tr('Kontrola ogólna'),
          date: today.subtract(const Duration(days: 30)),
          notes: tr('Wszystko w porządku')),
      HealthRecord(
          id: 'h7',
          category: HealthCategory.supplements,
          title: tr('Antiflexi'),
          date: today.subtract(const Duration(days: 14)),
          nextDue: today.add(const Duration(days: 16))),
    ];

    trainings = [];
    const pattern = [
      Discipline.igp,
      Discipline.canicross,
      Discipline.recovery,
      Discipline.obedience,
      Discipline.condition,
      Discipline.bikejoring,
      Discipline.nosework,
    ];
    for (var d = 84; d >= 1; d--) {
      if (rnd.nextDouble() < 0.28) continue;
      final disc = pattern[(84 - d) % pattern.length];
      final day = today.subtract(Duration(days: d)).add(Duration(hours: 17 + rnd.nextInt(3)));
      final km = disc.hasDistance && disc != Discipline.recovery
          ? double.parse((3 + rnd.nextDouble() * (disc == Discipline.bikejoring ? 10 : 5))
              .toStringAsFixed(1))
          : (disc == Discipline.recovery ? 2.0 : null);
      trainings.add(TrainingSession(
          id: 't$d',
          discipline: disc,
          date: day,
          durationMin: 25 + rnd.nextInt(50),
          distanceKm: km,
          rpe: disc == Discipline.recovery ? 2 : 4 + rnd.nextInt(5)));
    }
    // Trasy GPS dla ostatnich biegów (canicross / bikejoring).
    var withTrack = 0;
    for (final t in trainings.reversed) {
      if (withTrack >= 4) break;
      if (t.discipline != Discipline.canicross && t.discipline != Discipline.bikejoring) continue;
      final bike = t.discipline == Discipline.bikejoring;
      final trk = demoTrack(t.distanceKm!, bike ? 150 + rnd.nextDouble() * 30 : 250 + rnd.nextDouble() * 40, rnd);
      final splits = trk.splits().where((e) => e.meters >= 1000).map((e) => e.seconds);
      final secs = trk.points.last.t;
      t.distanceKm = double.parse((trk.meters / 1000).toStringAsFixed(2));
      t.movingSec = secs.round();
      t.durationMin = (secs / 60).round();
      t.maxSpeedKmh = double.parse(trk.maxSpeedKmh().toStringAsFixed(1));
      t.bestKmSec = splits.isEmpty ? null : splits.reduce(min).round();
      t.trackRef = await FileStore.saveText(trk.encode());
      withTrack++;
    }
    trainings.addAll([
      TrainingSession(
          id: 'p1',
          discipline: Discipline.igp,
          date: today.add(const Duration(days: 1, hours: 18)),
          durationMin: 60,
          rpe: 7,
          notes: tr('Obrona'),
          done: false),
      TrainingSession(
          id: 'p2',
          discipline: Discipline.canicross,
          date: today.add(const Duration(days: 2, hours: 17)),
          durationMin: 35,
          distanceKm: 6,
          rpe: 6,
          notes: tr('Interwały'),
          done: false),
    ]);

    events = [
      CalendarEvent(
          id: 'e1',
          type: EventType.show,
          title: tr('Wystawa ZKwP – Wrocław'),
          date: today.add(const Duration(days: 24, hours: 9))),
      CalendarEvent(
          id: 'e2',
          type: EventType.competition,
          title: tr('Egzamin BH-VT'),
          date: today.add(const Duration(days: 38, hours: 8))),
    ];
    shows = [
      ShowEntry(
          id: 's1',
          name: tr('Krajowa Wystawa Psów Rasowych'),
          place: tr('Poznań'),
          date: today.subtract(const Duration(days: 150)),
          type: ShowType.national,
          showClass: ShowClass.junior,
          status: ShowStatus.done,
          judge: tr('A. Nowak'),
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.zm}),
      ShowEntry(
          id: 's2',
          name: tr('Międzynarodowa Wystawa Psów'),
          place: tr('Kraków'),
          date: today.subtract(const Duration(days: 95)),
          type: ShowType.international,
          showClass: ShowClass.junior,
          status: ShowStatus.done,
          judge: tr('J. Kowalski'),
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.zm, ShowTitle.boj}),
      ShowEntry(
          id: 's3',
          name: tr('Krajowa Wystawa Psów Rasowych'),
          place: tr('Łódź'),
          date: today.subtract(const Duration(days: 40)),
          type: ShowType.national,
          showClass: ShowClass.intermediate,
          status: ShowStatus.done,
          judge: tr('M. Wiśniewska'),
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.cwc}),
      ShowEntry(
          id: 's4',
          name: tr('Wystawa ZKwP – Wrocław'),
          place: tr('Wrocław'),
          date: today.add(const Duration(days: 24, hours: 9)),
          type: ShowType.international,
          showClass: ShowClass.intermediate,
          status: ShowStatus.planned,
          entryDeadline: today.add(const Duration(days: 6)),
          fee: 180),
    ];
    events.removeWhere((e) => e.id == 'e1');
    documents = [
      DogDocument(id: 'd1', type: DocType.pedigree, title: tr('Rodowód ZKwP'), number: tr('PKR.I-12345'), issued: DateTime(now.year - 1, 8, 1)),
      DogDocument(id: 'd2', type: DocType.passport, title: tr('Paszport UE'), number: tr('PL 0123456'), issued: DateTime(now.year - 1, 7, 15)),
      DogDocument(id: 'd3', type: DocType.healthBook, title: tr('Książeczka zdrowia')),
      DogDocument(id: 'd4', type: DocType.results, title: tr('HD/ED wstępne'), issued: today.subtract(const Duration(days: 30)), notes: tr('HD A, ED 0')),
      DogDocument(id: 'd5', type: DocType.license, title: tr('Licencja sportowa IGP'), number: 'L-2026-071', expires: today.add(const Duration(days: 75))),
    ];
    gear = [
      GearItem(
          id: 'g1',
          category: GearCategory.harness,
          name: tr('Szelki canicross'),
          brand: tr('Non-stop Freemotion'),
          purchased: today.subtract(const Duration(days: 200)),
          price: 389,
          replaceAfterMonths: 18,
          maxKm: 1500,
          disciplines: {Discipline.canicross, Discipline.bikejoring}),
      GearItem(
          id: 'g2',
          category: GearCategory.bungee,
          name: tr('Linka z amortyzatorem'),
          brand: tr('Non-stop'),
          purchased: today.subtract(const Duration(days: 330)),
          price: 149,
          replaceAfterMonths: 12,
          maxKm: 800,
          disciplines: {Discipline.canicross, Discipline.bikejoring}),
      GearItem(
          id: 'g3',
          category: GearCategory.bike,
          name: tr('Rower MTB'),
          brand: tr('Kross'),
          purchased: today.subtract(const Duration(days: 500)),
          price: 3200,
          disciplines: {Discipline.bikejoring},
          notes: tr('Przegląd co 6 miesięcy')),
    ];
    goals = [
      Goal(id: 'c1', type: GoalType.exam, title: tr('BH-VT'), start: today.subtract(const Duration(days: 200)), done: true, doneDate: today.subtract(const Duration(days: 60))),
      Goal(id: 'c2', type: GoalType.exam, title: tr('IGP 1'), start: today.subtract(const Duration(days: 50)), deadline: DateTime(now.year + 1, 5, 1), manualProgress: 0.6),
      Goal(id: 'c3', type: GoalType.title, title: tr('Champion Polski'), start: today.subtract(const Duration(days: 150)), championship: Championship.pl),
      Goal(id: 'c4', type: GoalType.km, title: tr('1000 km w roku'), start: DateTime(now.year), deadline: DateTime(now.year, 12, 31), target: 1000),
      Goal(id: 'c5', type: GoalType.weight, title: tr('Waga docelowa 22 kg'), start: today.subtract(const Duration(days: 180)), target: 22),
    ];
    await NutritionStore.instance.loadDemo();
    await HeatStore.instance.loadDemo();
    await _save();
  }
}

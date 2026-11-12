import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' show Icons, Color;
import 'package:shared_preferences/shared_preferences.dart';

import 'files/file_store.dart';
import 'models.dart';
import 'models_ext.dart';
import 'notifications.dart';

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

/// Cały stan aplikacji, zapisywany lokalnie na telefonie.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _key = 'k9coach_data_v1';
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

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      dog = j['dog'] == null ? null : Dog.fromJson(j['dog']);
      weights = [for (final e in (j['weights'] as List? ?? [])) WeightEntry.fromJson(e)];
      health = [for (final e in (j['health'] as List? ?? [])) HealthRecord.fromJson(e)];
      trainings = [for (final e in (j['trainings'] as List? ?? [])) TrainingSession.fromJson(e)];
      events = [for (final e in (j['events'] as List? ?? [])) CalendarEvent.fromJson(e)];
      shows = [for (final e in (j['shows'] as List? ?? [])) ShowEntry.fromJson(e)];
      documents = [for (final e in (j['documents'] as List? ?? [])) DogDocument.fromJson(e)];
      gear = [for (final e in (j['gear'] as List? ?? [])) GearItem.fromJson(e)];
      goals = [for (final e in (j['goals'] as List? ?? [])) Goal.fromJson(e)];
    } catch (e) {
      debugPrint('Błąd odczytu danych: $e');
    }
  }

  Future<void> _save() async {
    _sort();
    notifyListeners();
    await _prefs.setString(
        _key,
        jsonEncode({
          'dog': dog?.toJson(),
          'weights': weights.map((e) => e.toJson()).toList(),
          'health': health.map((e) => e.toJson()).toList(),
          'trainings': trainings.map((e) => e.toJson()).toList(),
          'events': events.map((e) => e.toJson()).toList(),
          'shows': shows.map((e) => e.toJson()).toList(),
          'documents': documents.map((e) => e.toJson()).toList(),
          'gear': gear.map((e) => e.toJson()).toList(),
          'goals': goals.map((e) => e.toJson()).toList(),
        }));
    await Notifications.instance.reschedule(this);
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

  Future<void> saveDog(Dog d) async {
    final oldWeight = dog?.weightKg;
    dog = d;
    if (d.weightKg != null && d.weightKg != oldWeight) {
      final today = dayOnly(DateTime.now());
      weights.removeWhere((w) => sameDay(w.date, today));
      weights.add(WeightEntry(id: newId(), date: today, kg: d.weightKg!));
    }
    await _save();
  }

  Future<void> addWeight(WeightEntry w) async {
    weights.removeWhere((e) => sameDay(e.date, w.date));
    weights.add(w);
    _sort();
    if (dog != null && weights.isNotEmpty) dog!.weightKg = weights.last.kg;
    await _save();
  }

  Future<void> deleteWeight(WeightEntry w) async {
    weights.removeWhere((e) => e.id == w.id);
    if (dog != null && weights.isNotEmpty) dog!.weightKg = weights.last.kg;
    await _save();
  }

  Future<void> resetAll() async {
    dog = null;
    weights = [];
    health = [];
    trainings = [];
    events = [];
    for (final d in documents) {
      for (final i in d.images) {
        await FileStore.delete(i);
      }
    }
    for (final g in gear) {
      if (g.photo != null) await FileStore.delete(g.photo!);
    }
    shows = [];
    documents = [];
    gear = [];
    goals = [];
    await _save();
  }

  // --- Zdrowie --------------------------------------------------------------

  Future<void> upsertHealth(HealthRecord r) async {
    health.removeWhere((e) => e.id == r.id);
    health.add(r);
    await _save();
  }

  Future<void> deleteHealth(HealthRecord r) async {
    health.removeWhere((e) => e.id == r.id);
    await _save();
  }

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

  Future<void> upsertTraining(TrainingSession t) async {
    trainings.removeWhere((e) => e.id == t.id);
    trainings.add(t);
    await _save();
  }

  Future<void> deleteTraining(TrainingSession t) async {
    trainings.removeWhere((e) => e.id == t.id);
    await _save();
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
      return const Readiness(50, 0, 'Brak danych',
          'Dodaj kilka treningów, a policzę formę i ryzyko przetrenowania.', 0);
    }
    final ratio = chronic < 1 ? 2.0 : acute / chronic;
    // Wynik: 100 przy ratio 1.05, spada w obie strony.
    final score = (100 - (ratio - 1.05).abs() * 90).clamp(5, 100).round();
    if (ratio < 0.8) {
      return Readiness(score, ratio, 'Wypoczęty',
          'Obciążenie spadło. Pies jest gotowy na mocniejszy trening.', 0);
    } else if (ratio <= 1.3) {
      return Readiness(score, ratio, 'Optymalna forma',
          'Obciążenie w bezpiecznym zakresie. Kontynuuj plan.', 1);
    } else if (ratio <= 1.5) {
      return Readiness(score, ratio, 'Uwaga',
          'Obciążenie rośnie szybko. Zaplanuj lżejszy dzień lub regenerację.', 2);
    }
    return Readiness(score, ratio, 'Ryzyko przetrenowania',
        'Ten tydzień jest dużo cięższy niż zwykle. Zalecany dzień regeneracji.', 3);
  }

  // --- Kalendarz -----------------------------------------------------------

  Future<void> upsertEvent(CalendarEvent e) async {
    events.removeWhere((x) => x.id == e.id);
    events.add(e);
    await _save();
  }

  Future<void> deleteEvent(CalendarEvent e) async {
    events.removeWhere((x) => x.id == e.id);
    await _save();
  }

  List<AgendaItem> agendaFor(DateTime day) =>
      agendaBetween(dayOnly(day), dayOnly(day).add(const Duration(days: 1)));

  List<AgendaItem> agendaBetween(DateTime from, DateTime to) {
    bool inRange(DateTime d) => !d.isBefore(from) && d.isBefore(to);
    final items = <AgendaItem>[
      for (final t in trainings)
        if (inRange(t.date))
          AgendaItem(
              date: t.date,
              title: 'Trening ${t.discipline.label}',
              subtitle: t.done ? 'Wykonany' : 'Zaplanowany',
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
              subtitle: 'Wystawa · ${sh.status.label}',
              icon: Icons.emoji_events_rounded,
              color: const Color(0xFFFFB020),
              source: sh),
      for (final sh in shows)
        if (sh.entryDeadline != null &&
            (sh.status == ShowStatus.planned) &&
            inRange(sh.entryDeadline!))
          AgendaItem(
              date: sh.entryDeadline!,
              title: 'Zgłoszenie: ${sh.name}',
              subtitle: 'Termin zgłoszeń',
              icon: Icons.assignment_late_rounded,
              color: const Color(0xFF5E8BFF),
              source: sh),
      for (final d in documents)
        if (d.expires != null && inRange(d.expires!))
          AgendaItem(
              date: d.expires!,
              title: 'Ważność: ${d.title}',
              subtitle: d.type.label,
              icon: d.type.icon,
              color: const Color(0xFFFF453A),
              source: d),
      for (final g in gear)
        if (!g.retired && g.replaceDate != null && inRange(g.replaceDate!))
          AgendaItem(
              date: g.replaceDate!,
              title: 'Wymiana: ${g.name}',
              subtitle: 'Sprzęt',
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

  Future<void> upsertShow(ShowEntry e) async {
    shows.removeWhere((x) => x.id == e.id);
    shows.add(e);
    await _save();
  }

  Future<void> deleteShow(ShowEntry e) async {
    shows.removeWhere((x) => x.id == e.id);
    await _save();
  }

  Future<void> upsertDocument(DogDocument e) async {
    documents.removeWhere((x) => x.id == e.id);
    documents.add(e);
    await _save();
  }

  Future<void> deleteDocument(DogDocument e) async {
    for (final i in e.images) {
      await FileStore.delete(i);
    }
    documents.removeWhere((x) => x.id == e.id);
    await _save();
  }

  Future<void> upsertGear(GearItem e) async {
    gear.removeWhere((x) => x.id == e.id);
    gear.add(e);
    await _save();
  }

  Future<void> deleteGear(GearItem e) async {
    if (e.photo != null) await FileStore.delete(e.photo!);
    gear.removeWhere((x) => x.id == e.id);
    await _save();
  }

  Future<void> upsertGoal(Goal e) async {
    goals.removeWhere((x) => x.id == e.id);
    goals.add(e);
    await _save();
  }

  Future<void> deleteGoal(Goal e) async {
    goals.removeWhere((x) => x.id == e.id);
    await _save();
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
        final n = titleCount(c.title);
        return (g.done ? 1 : n / c.required, '$n / ${c.required} × ${c.title.short}');
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
      name: 'Gamora',
      breed: 'Owczarek belgijski Malinois',
      female: true,
      birthDate: DateTime(now.year - 1, now.month - 6, 7),
      weightKg: 20.5,
      heightCm: 54,
      bcs: 4,
      chip: '616093901234567',
      pedigree: 'ZKwP-12345',
      targetWeightKg: 22,
      weeklyKmGoal: 35,
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
          title: 'Szczepienie przeciw wściekliźnie',
          date: today.subtract(const Duration(days: 355)),
          nextDue: today.add(const Duration(days: 10))),
      HealthRecord(
          id: 'h2',
          category: HealthCategory.vaccination,
          title: 'DHPPi + L4',
          date: today.subtract(const Duration(days: 120)),
          nextDue: today.add(const Duration(days: 245))),
      HealthRecord(
          id: 'h3',
          category: HealthCategory.deworming,
          title: 'Milbemax',
          date: today.subtract(const Duration(days: 40)),
          nextDue: today.add(const Duration(days: 50))),
      HealthRecord(
          id: 'h4',
          category: HealthCategory.ticks,
          title: 'Bravecto',
          date: today.subtract(const Duration(days: 70)),
          nextDue: today.add(const Duration(days: 20))),
      HealthRecord(
          id: 'h5',
          category: HealthCategory.tests,
          title: 'HD/ED wstępne',
          date: today.subtract(const Duration(days: 30)),
          notes: 'HD A, ED 0'),
      HealthRecord(
          id: 'h6',
          category: HealthCategory.vet,
          title: 'Kontrola ogólna',
          date: today.subtract(const Duration(days: 30)),
          notes: 'Wszystko w porządku'),
      HealthRecord(
          id: 'h7',
          category: HealthCategory.supplements,
          title: 'Antiflexi',
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
    trainings.addAll([
      TrainingSession(
          id: 'p1',
          discipline: Discipline.igp,
          date: today.add(const Duration(days: 1, hours: 18)),
          durationMin: 60,
          rpe: 7,
          notes: 'Obrona',
          done: false),
      TrainingSession(
          id: 'p2',
          discipline: Discipline.canicross,
          date: today.add(const Duration(days: 2, hours: 17)),
          durationMin: 35,
          distanceKm: 6,
          rpe: 6,
          notes: 'Interwały',
          done: false),
    ]);

    events = [
      CalendarEvent(
          id: 'e1',
          type: EventType.show,
          title: 'Wystawa ZKwP – Wrocław',
          date: today.add(const Duration(days: 24, hours: 9))),
      CalendarEvent(
          id: 'e2',
          type: EventType.competition,
          title: 'Egzamin BH-VT',
          date: today.add(const Duration(days: 38, hours: 8))),
    ];
    shows = [
      ShowEntry(
          id: 's1',
          name: 'Krajowa Wystawa Psów Rasowych',
          place: 'Poznań',
          date: today.subtract(const Duration(days: 150)),
          type: ShowType.national,
          showClass: ShowClass.junior,
          status: ShowStatus.done,
          judge: 'A. Nowak',
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.jcwc, ShowTitle.zm}),
      ShowEntry(
          id: 's2',
          name: 'Międzynarodowa Wystawa Psów',
          place: 'Kraków',
          date: today.subtract(const Duration(days: 95)),
          type: ShowType.international,
          showClass: ShowClass.junior,
          status: ShowStatus.done,
          judge: 'J. Kowalski',
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.jcwc, ShowTitle.zm, ShowTitle.boj}),
      ShowEntry(
          id: 's3',
          name: 'Krajowa Wystawa Psów Rasowych',
          place: 'Łódź',
          date: today.subtract(const Duration(days: 40)),
          type: ShowType.national,
          showClass: ShowClass.intermediate,
          status: ShowStatus.done,
          judge: 'M. Wiśniewska',
          grade: 'Doskonała',
          placement: 1,
          titles: {ShowTitle.cwc}),
      ShowEntry(
          id: 's4',
          name: 'Wystawa ZKwP – Wrocław',
          place: 'Wrocław',
          date: today.add(const Duration(days: 24, hours: 9)),
          type: ShowType.international,
          showClass: ShowClass.intermediate,
          status: ShowStatus.planned,
          entryDeadline: today.add(const Duration(days: 6)),
          fee: 180),
    ];
    events.removeWhere((e) => e.id == 'e1');
    documents = [
      DogDocument(id: 'd1', type: DocType.pedigree, title: 'Rodowód ZKwP', number: 'PKR.I-12345', issued: DateTime(now.year - 1, 8, 1)),
      DogDocument(id: 'd2', type: DocType.passport, title: 'Paszport UE', number: 'PL 0123456', issued: DateTime(now.year - 1, 7, 15)),
      DogDocument(id: 'd3', type: DocType.healthBook, title: 'Książeczka zdrowia'),
      DogDocument(id: 'd4', type: DocType.results, title: 'HD/ED wstępne', issued: today.subtract(const Duration(days: 30)), notes: 'HD A, ED 0'),
      DogDocument(id: 'd5', type: DocType.license, title: 'Licencja sportowa IGP', number: 'L-2026-071', expires: today.add(const Duration(days: 75))),
    ];
    gear = [
      GearItem(
          id: 'g1',
          category: GearCategory.harness,
          name: 'Szelki canicross',
          brand: 'Non-stop Freemotion',
          purchased: today.subtract(const Duration(days: 200)),
          price: 389,
          replaceAfterMonths: 18,
          maxKm: 1500,
          disciplines: {Discipline.canicross, Discipline.bikejoring}),
      GearItem(
          id: 'g2',
          category: GearCategory.bungee,
          name: 'Linka z amortyzatorem',
          brand: 'Non-stop',
          purchased: today.subtract(const Duration(days: 330)),
          price: 149,
          replaceAfterMonths: 12,
          maxKm: 800,
          disciplines: {Discipline.canicross, Discipline.bikejoring}),
      GearItem(
          id: 'g3',
          category: GearCategory.bike,
          name: 'Rower MTB',
          brand: 'Kross',
          purchased: today.subtract(const Duration(days: 500)),
          price: 3200,
          disciplines: {Discipline.bikejoring},
          notes: 'Przegląd co 6 miesięcy'),
    ];
    goals = [
      Goal(id: 'c1', type: GoalType.exam, title: 'BH-VT', start: today.subtract(const Duration(days: 200)), done: true, doneDate: today.subtract(const Duration(days: 60))),
      Goal(id: 'c2', type: GoalType.exam, title: 'IGP 1', start: today.subtract(const Duration(days: 50)), deadline: DateTime(now.year + 1, 5, 1), manualProgress: 0.6),
      Goal(id: 'c3', type: GoalType.title, title: 'Champion Polski', start: today.subtract(const Duration(days: 150)), championship: Championship.pl),
      Goal(id: 'c4', type: GoalType.km, title: '1000 km w roku', start: DateTime(now.year), deadline: DateTime(now.year, 12, 31), target: 1000),
      Goal(id: 'c5', type: GoalType.weight, title: 'Waga docelowa 22 kg', start: today.subtract(const Duration(days: 180)), target: 22),
    ];
    await _save();
  }
}

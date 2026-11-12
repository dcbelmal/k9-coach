import 'dart:convert';

import 'package:material_ui/material_ui.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${(DateTime.now().hashCode % 997)}';

DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);

// ---------------------------------------------------------------------------
// Pies
// ---------------------------------------------------------------------------

class Dog {
  String name;
  String breed;
  bool female;
  DateTime? birthDate;
  double? weightKg;
  double? heightCm;
  int? bcs; // 1-9
  String chip;
  String pedigree;
  String notes;
  String? photoBase64;
  double? targetWeightKg;
  double weeklyKmGoal;

  Dog({
    required this.name,
    this.breed = '',
    this.female = true,
    this.birthDate,
    this.weightKg,
    this.heightCm,
    this.bcs,
    this.chip = '',
    this.pedigree = '',
    this.notes = '',
    this.photoBase64,
    this.targetWeightKg,
    this.weeklyKmGoal = 30,
  });

  String get ageLabel {
    if (birthDate == null) return '';
    final now = DateTime.now();
    var months = (now.year - birthDate!.year) * 12 + now.month - birthDate!.month;
    if (now.day < birthDate!.day) months--;
    if (months < 0) return '';
    if (months < 24) return '$months mies.';
    final y = months ~/ 12, m = months % 12;
    final yl = y < 5 ? 'lata' : 'lat';
    return m == 0 ? '$y $yl' : '$y $yl $m mies.';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'breed': breed,
        'female': female,
        'birthDate': birthDate?.toIso8601String(),
        'weightKg': weightKg,
        'heightCm': heightCm,
        'bcs': bcs,
        'chip': chip,
        'pedigree': pedigree,
        'notes': notes,
        'photo': photoBase64,
        'targetWeightKg': targetWeightKg,
        'weeklyKmGoal': weeklyKmGoal,
      };

  factory Dog.fromJson(Map<String, dynamic> j) => Dog(
        name: j['name'] ?? '',
        breed: j['breed'] ?? '',
        female: j['female'] ?? true,
        birthDate: _date(j['birthDate']),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        bcs: j['bcs'] as int?,
        chip: j['chip'] ?? '',
        pedigree: j['pedigree'] ?? '',
        notes: j['notes'] ?? '',
        photoBase64: j['photo'] as String?,
        targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
        weeklyKmGoal: (j['weeklyKmGoal'] as num?)?.toDouble() ?? 30,
      );
}

class WeightEntry {
  final String id;
  DateTime date;
  double kg;
  WeightEntry({required this.id, required this.date, required this.kg});

  Map<String, dynamic> toJson() =>
      {'id': id, 'date': date.toIso8601String(), 'kg': kg};
  factory WeightEntry.fromJson(Map<String, dynamic> j) => WeightEntry(
      id: j['id'], date: DateTime.parse(j['date']), kg: (j['kg'] as num).toDouble());
}

// ---------------------------------------------------------------------------
// Zdrowie
// ---------------------------------------------------------------------------

enum HealthCategory {
  vaccination('Szczepienia', Icons.vaccines_rounded, Color(0xFF34C759)),
  deworming('Odrobaczanie', Icons.medication_rounded, Color(0xFF30B0C7)),
  ticks('Kleszcze / pasożyty', Icons.bug_report_rounded, Color(0xFFFF6B3D)),
  tests('Badania (HD/ED, DNA, oczy)', Icons.science_rounded, Color(0xFF5E8BFF)),
  vet('Wizyty u weterynarza', Icons.local_hospital_rounded, Color(0xFFFF453A)),
  supplements('Suplementacja', Icons.spa_rounded, Color(0xFFF5A524));

  final String label;
  final IconData icon;
  final Color color;
  const HealthCategory(this.label, this.icon, this.color);
}

class HealthRecord {
  final String id;
  HealthCategory category;
  String title;
  DateTime date;
  DateTime? nextDue;
  String notes;
  bool remind;

  HealthRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.date,
    this.nextDue,
    this.notes = '',
    this.remind = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'title': title,
        'date': date.toIso8601String(),
        'nextDue': nextDue?.toIso8601String(),
        'notes': notes,
        'remind': remind,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
        id: j['id'],
        category: HealthCategory.values.byName(j['category']),
        title: j['title'] ?? '',
        date: DateTime.parse(j['date']),
        nextDue: _date(j['nextDue']),
        notes: j['notes'] ?? '',
        remind: j['remind'] ?? true,
      );
}

// ---------------------------------------------------------------------------
// Trening
// ---------------------------------------------------------------------------

enum Discipline {
  igp('IGP', Icons.sports_martial_arts_rounded, Color(0xFFF5821F), false),
  bhvt('BH-VT', Icons.emoji_events_rounded, Color(0xFFFFB020), false),
  canicross('Canicross', Icons.directions_run_rounded, Color(0xFFFF5A36), true),
  bikejoring('Bikejoring', Icons.directions_bike_rounded, Color(0xFF5E8BFF), true),
  obedience('Obedience', Icons.pets_rounded, Color(0xFF34C759), false),
  nosework('Nosework', Icons.travel_explore_rounded, Color(0xFFBF5AF2), false),
  condition('Kondycja', Icons.fitness_center_rounded, Color(0xFF30B0C7), true),
  recovery('Regeneracja', Icons.self_improvement_rounded, Color(0xFF8E8E93), true);

  final String label;
  final IconData icon;
  final Color color;
  final bool hasDistance;
  const Discipline(this.label, this.icon, this.color, this.hasDistance);
}

class TrainingSession {
  final String id;
  Discipline discipline;
  DateTime date;
  int durationMin;
  double? distanceKm;
  int rpe; // intensywność 1-10
  String notes;
  bool done;

  TrainingSession({
    required this.id,
    required this.discipline,
    required this.date,
    this.durationMin = 30,
    this.distanceKm,
    this.rpe = 5,
    this.notes = '',
    this.done = true,
  });

  /// Obciążenie treningowe (sesyjne RPE).
  double get load => discipline == Discipline.recovery ? durationMin * 1.0 : durationMin * rpe * 1.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'discipline': discipline.name,
        'date': date.toIso8601String(),
        'durationMin': durationMin,
        'distanceKm': distanceKm,
        'rpe': rpe,
        'notes': notes,
        'done': done,
      };

  factory TrainingSession.fromJson(Map<String, dynamic> j) => TrainingSession(
        id: j['id'],
        discipline: Discipline.values.byName(j['discipline']),
        date: DateTime.parse(j['date']),
        durationMin: j['durationMin'] ?? 30,
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        rpe: j['rpe'] ?? 5,
        notes: j['notes'] ?? '',
        done: j['done'] ?? true,
      );
}

// ---------------------------------------------------------------------------
// Kalendarz
// ---------------------------------------------------------------------------

enum EventType {
  competition('Zawody', Icons.military_tech_rounded, Color(0xFFFFB020)),
  show('Wystawa', Icons.emoji_events_rounded, Color(0xFFF5821F)),
  vet('Wizyta', Icons.local_hospital_rounded, Color(0xFFFF453A)),
  reminder('Przypomnienie', Icons.notifications_active_rounded, Color(0xFF5E8BFF)),
  other('Inne', Icons.event_rounded, Color(0xFF8E8E93));

  final String label;
  final IconData icon;
  final Color color;
  const EventType(this.label, this.icon, this.color);
}

class CalendarEvent {
  final String id;
  EventType type;
  String title;
  DateTime date;
  String notes;
  bool remind;

  CalendarEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.notes = '',
    this.remind = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'date': date.toIso8601String(),
        'notes': notes,
        'remind': remind,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
        id: j['id'],
        type: EventType.values.byName(j['type']),
        title: j['title'] ?? '',
        date: DateTime.parse(j['date']),
        notes: j['notes'] ?? '',
        remind: j['remind'] ?? true,
      );
}

/// Ujednolicony wpis kalendarza (trening, zdrowie, wydarzenie).
class AgendaItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Object source;
  const AgendaItem(
      {required this.date,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.color,
      required this.source});
}

String encodeList(List<dynamic> items) =>
    jsonEncode(items.map((e) => e.toJson()).toList());

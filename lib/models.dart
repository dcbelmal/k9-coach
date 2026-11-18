import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'l10n/l10n.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${(DateTime.now().hashCode % 997)}';

DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);

// ---------------------------------------------------------------------------
// Pies
// ---------------------------------------------------------------------------

/// Poziom aktywności psa (kreator profilu).
enum DogActivity {
  low('Niski', 'Krótkie spacery, dużo odpoczynku'),
  medium('Średni', 'Codzienne spacery i zabawa'),
  high('Wysoki', 'Regularne treningi, dużo biegania'),
  veryHigh('Bardzo wysoki', 'Sport wyczynowy lub praca codziennie');

  final String _label;
  String get label => tr(_label);
  final String _hint;
  String get hint => tr(_hint);
  const DogActivity(this._label, this._hint);
}

/// Cel użytkowania psa – decyduje o modułach treningowych.
enum DogPurpose {
  family('Pies rodzinny', Icons.family_restroom_rounded),
  sport('Sport', Icons.directions_run_rounded),
  working('Pies pracujący', Icons.shield_rounded),
  breeding('Hodowla', Icons.child_friendly_rounded),
  recreation('Rekreacja', Icons.landscape_rounded);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  const DogPurpose(this._label, this.icon);
}

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
  int? fciGroup; // 1-10
  bool? workingTrial; // rasa podlega próbom pracy (C.I.B.)
  bool neutered; // kastrowany / wysterylizowana
  DogActivity? activity;
  DogPurpose? purpose;
  String? breedId; // rasa z lokalnej bazy ras
  bool mixed; // mieszaniec

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
    this.fciGroup,
    this.workingTrial,
    this.neutered = false,
    this.activity,
    this.purpose,
    this.breedId,
    this.mixed = false,
  });

  /// Czy profil ma już dane z kreatora (starsze profile ich nie mają).
  bool get profileComplete => activity != null && purpose != null;

  String get sexLabel => female ? tr('Suka') : tr('Pies');
  String get reproLabel => female
      ? (neutered ? tr('Wysterylizowana') : tr('Niewysterylizowana'))
      : (neutered ? tr('Kastrowany') : tr('Niekastrowany'));

  String get ageLabel {
    if (birthDate == null) return '';
    final now = DateTime.now();
    var months = (now.year - birthDate!.year) * 12 + now.month - birthDate!.month;
    if (now.day < birthDate!.day) months--;
    if (months < 0) return '';
    if (months < 24) return tr('{0} mies.', [months]);
    final y = months ~/ 12, m = months % 12;
    final yl = y < 5 ? tr('lata') : tr('lat');
    return m == 0 ? '$y $yl' : tr('{0} {1} {2} mies.', [y, yl, m]);
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
        'fciGroup': fciGroup,
        'workingTrial': workingTrial,
        'neutered': neutered,
        'activity': activity?.name,
        'purpose': purpose?.name,
        'breedId': breedId,
        'mixed': mixed,
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
        fciGroup: j['fciGroup'] as int?,
        workingTrial: j['workingTrial'] as bool?,
        neutered: j['neutered'] ?? false,
        activity: DogActivity.values.asNameMap()[j['activity']],
        purpose: DogPurpose.values.asNameMap()[j['purpose']],
        breedId: j['breedId'] as String?,
        mixed: j['mixed'] ?? false,
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

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final Color color;
  const HealthCategory(this._label, this.icon, this.color);
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
  walk('Spacer', Icons.directions_walk_rounded, Color(0xFFC49A6C), true),
  condition('Kondycja', Icons.fitness_center_rounded, Color(0xFF30B0C7), true),
  recovery('Regeneracja', Icons.self_improvement_rounded, Color(0xFF8E8E93), true);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final Color color;
  final bool hasDistance;
  const Discipline(this._label, this.icon, this.color, this.hasDistance);

  /// Krótkie wyjaśnienie, co wpisywać pod daną dyscypliną.
  String get description => switch (this) {
        igp => tr('Sport użytkowy: tropienie, posłuszeństwo i obrona.'),
        bhvt => tr('Przygotowanie do egzaminu psa towarzyszącego.'),
        canicross => tr('Bieg z psem w pasie i szelkach.'),
        bikejoring => tr('Rower lub hulajnoga, pies ciągnie w szelkach.'),
        obedience => tr('Precyzyjne posłuszeństwo sportowe.'),
        nosework => tr('Praca węchowa i szukanie zapachów.'),
        walk => tr('Zwykły spacer z psem, bez treningu.'),
        condition => tr('Budowanie siły i sprawności: podbiegi, pływanie, ćwiczenia na niestabilnym podłożu, równy kłus przy rowerze.'),
        recovery => tr('Lekki dzień po wysiłku: rozciąganie, masaż, bardzo spokojne rozluźnienie.'),
      };
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
  String? trackRef; // trasa GPS zapisana w pliku
  int? movingSec; // czas ruchu bez pauz
  double? maxSpeedKmh;
  int? bestKmSec; // najszybszy kilometr

  bool get hasTrack => trackRef != null;

  TrainingSession({
    required this.id,
    required this.discipline,
    required this.date,
    this.durationMin = 30,
    this.distanceKm,
    this.rpe = 5,
    this.notes = '',
    this.done = true,
    this.trackRef,
    this.movingSec,
    this.maxSpeedKmh,
    this.bestKmSec,
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
        'track': trackRef,
        'movingSec': movingSec,
        'maxSpeed': maxSpeedKmh,
        'bestKm': bestKmSec,
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
        trackRef: j['track'],
        movingSec: j['movingSec'],
        maxSpeedKmh: (j['maxSpeed'] as num?)?.toDouble(),
        bestKmSec: j['bestKm'],
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

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final Color color;
  const EventType(this._label, this.icon, this.color);
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

const romanNumerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];

/// Grupy FCI (nazwy skrócone).
const fciGroupNames = [
  'Owczarki i psy pasterskie',
  'Pinczery, sznaucery, molosy, psy do bydła',
  'Teriery',
  'Jamniki',
  'Szpice i psy w typie pierwotnym',
  'Psy gończe i posokowce',
  'Wyżły',
  'Aportery, płochacze, psy dowodne',
  'Psy ozdobne i do towarzystwa',
  'Charty',
];

String fciGroupLabel(int g) => tr('Grupa {0} – {1}', [romanNumerals[g - 1], tr(fciGroupNames[g - 1])]);

/// Podpowiedź grupy FCI na podstawie nazwy rasy.
int? guessFciGroup(String breed) {
  final b = breed.toLowerCase();
  const map = <String, int>{
    'owczar': 1, 'malinois': 1, 'collie': 1, 'border': 1, 'australijsk': 1, 'corgi': 1, 'komondor': 1, 'puli': 1,
    'rottweil': 2, 'doberman': 2, 'bokser': 2, 'sznaucer': 2, 'pinczer': 2, 'dog niem': 2, 'mastif': 2, 'nowofundland': 2,
    'berneński': 2, 'cane corso': 2, 'leonberg': 2, 'buldog angielski': 2, 'bernardyn': 2, 'shar': 2,
    'terier': 3, 'yorkshire': 3, 'bull terier': 3,
    'jamnik': 4,
    'husky': 5, 'malamut': 5, 'akita': 5, 'szpic': 5, 'shiba': 5, 'samoyed': 5, 'basenji': 5, 'chow': 5,
    'gończ': 6, 'beagle': 6, 'posokow': 6, 'dalmaty': 6, 'basset': 6, 'rhodesian': 6,
    'wyżeł': 7, 'wyżel': 7, 'seter': 7, 'pointer': 7, 'weimar': 7,
    'retriever': 8, 'labrador': 8, 'golden': 8, 'spaniel': 8, 'cocker': 8,
    'pudel': 9, 'chihuahua': 9, 'maltańczyk': 9, 'shih': 9, 'buldog francuski': 9, 'mops': 9, 'cavalier': 9, 'papillon': 9, 'havanese': 9, 'bichon': 9,
    'chart': 10, 'greyhound': 10, 'whippet': 10, 'saluki': 10, 'borzoj': 10, 'afgań': 10,
  };
  for (final e in map.entries) {
    if (b.contains(e.key)) return e.value;
  }
  return null;
}

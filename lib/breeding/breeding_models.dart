import 'package:material_ui/material_ui.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

enum MatingMethod {
  natural('Naturalne'),
  ai('Inseminacja');

  final String _label;
  String get label => tr(_label);
  const MatingMethod(this._label);
}

enum PregnancyStatus {
  waiting('Czekamy na potwierdzenie', Color(0xFFFFC53D)),
  confirmed('Ciąża potwierdzona', Color(0xFF34C759)),
  notPregnant('Nie zaszła', Color(0xFF8E8E93)),
  whelped('Po porodzie', Color(0xFF5E8BFF));

  final String _label;
  String get label => tr(_label);
  final Color color;
  const PregnancyStatus(this._label, this.color);
}

class PuppyWeight {
  final DateTime date;
  final int grams;
  const PuppyWeight(this.date, this.grams);

  Map<String, dynamic> toJson() => {'d': date.toIso8601String(), 'g': grams};
  factory PuppyWeight.fromJson(Map<String, dynamic> j) => PuppyWeight(DateTime.parse(j['d']), (j['g'] as num).toInt());
}

class Puppy {
  final String id;
  String name;
  bool female;
  String color;
  String notes;
  List<PuppyWeight> weights;

  Puppy({required this.id, required this.name, this.female = true, this.color = '', this.notes = '', List<PuppyWeight>? weights})
      : weights = weights ?? [];

  void sortWeights() => weights.sort((a, b) => a.date.compareTo(b.date));

  int? get birthGrams => weights.isEmpty ? null : weights.first.grams;
  int? get lastGrams => weights.isEmpty ? null : weights.last.grams;

  /// Zmiana od poprzedniego ważenia (g) – null, gdy mniej niż 2 ważenia.
  int? get lastChange => weights.length < 2 ? null : weights.last.grams - weights[weights.length - 2].grams;

  /// Szczenię straciło na wadze od poprzedniego ważenia (ocenę daje PuppyGrowth.alert).
  bool get losing => (lastChange ?? 0) < 0;

  void setWeight(DateTime date, int grams) {
    weights.removeWhere((w) => _day(w.date) == _day(date));
    weights.add(PuppyWeight(_day(date), grams));
    sortWeights();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'female': female,
        'color': color,
        'notes': notes,
        'weights': weights.map((w) => w.toJson()).toList(),
      };

  factory Puppy.fromJson(Map<String, dynamic> j) => Puppy(
        id: j['id'],
        name: j['name'] ?? '',
        female: j['female'] ?? true,
        color: j['color'] ?? '',
        notes: j['notes'] ?? '',
        weights: [for (final w in (j['weights'] as List? ?? [])) PuppyWeight.fromJson(w)],
      )..sortWeights();
}

class Litter {
  DateTime born;
  int stillborn;
  String notes;
  List<Puppy> puppies;

  Litter({required this.born, this.stillborn = 0, this.notes = '', List<Puppy>? puppies}) : puppies = puppies ?? [];

  int get males => puppies.where((p) => !p.female).length;
  int get females => puppies.where((p) => p.female).length;

  /// Wiek miotu w dniach (0 = dzień porodu).
  int ageDays(DateTime now) => _day(now).difference(_day(born)).inCalDays;

  Map<String, dynamic> toJson() => {
        'born': born.toIso8601String(),
        'stillborn': stillborn,
        'notes': notes,
        'puppies': puppies.map((p) => p.toJson()).toList(),
      };

  factory Litter.fromJson(Map<String, dynamic> j) => Litter(
        born: DateTime.parse(j['born']),
        stillborn: j['stillborn'] ?? 0,
        notes: j['notes'] ?? '',
        puppies: [for (final p in (j['puppies'] as List? ?? [])) Puppy.fromJson(p)],
      );
}

/// Jedno krycie (może obejmować 1–3 zbliżenia w kolejnych dniach).
class Mating {
  final String id;
  List<DateTime> dates;
  String partner; // reproduktor (dla suki) albo suka (dla psa)
  MatingMethod method;
  DateTime? ovulation; // z badania progesteronu
  String notes;
  PregnancyStatus status;
  Litter? litter;

  Mating({
    required this.id,
    required List<DateTime> dates,
    this.partner = '',
    this.method = MatingMethod.natural,
    this.ovulation,
    this.notes = '',
    this.status = PregnancyStatus.waiting,
    this.litter,
  }) : dates = (dates.map(_day).toSet().toList()..sort());

  DateTime get first => dates.first;
  DateTime get last => dates.last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dates': dates.map((d) => d.toIso8601String()).toList(),
        'partner': partner,
        'method': method.name,
        'ovulation': ovulation?.toIso8601String(),
        'notes': notes,
        'status': status.name,
        'litter': litter?.toJson(),
      };

  factory Mating.fromJson(Map<String, dynamic> j) => Mating(
        id: j['id'],
        dates: [for (final d in (j['dates'] as List)) DateTime.parse(d)],
        partner: j['partner'] ?? '',
        method: MatingMethod.values.asNameMap()[j['method']] ?? MatingMethod.natural,
        ovulation: j['ovulation'] == null ? null : DateTime.parse(j['ovulation']),
        notes: j['notes'] ?? '',
        status: PregnancyStatus.values.asNameMap()[j['status']] ?? PregnancyStatus.waiting,
        litter: j['litter'] == null ? null : Litter.fromJson(j['litter']),
      );
}

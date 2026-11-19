import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Objawy obserwowane w trakcie cieczki (polskie klucze tłumaczeń).
const heatSymptoms = <String>[
  'Krwawienie',
  'Obrzęk sromu',
  'Jaśniejsza wydzielina',
  'Przyjmuje psa / odstawia ogon',
  'Częste znaczenie moczem',
  'Zmiana zachowania',
];

enum HeatTestType {
  progesterone('Progesteron'),
  cytology('Cytologia');

  final String _label;
  String get label => tr(_label);
  const HeatTestType(this._label);
}

/// Wynik cytologii pochwy – tak, jak opisał go lekarz weterynarii.
enum CytologyResult {
  proestrus('obraz proestrus'),
  estrus('obraz estrus'),
  diestrus('obraz diestrus'),
  other('inny / niejednoznaczny');

  final String _label;
  String get label => tr(_label);
  const CytologyResult(this._label);
}

/// Jedno badanie w trakcie cieczki (progesteron albo cytologia).
class HeatTest {
  final String id;
  DateTime date; // data pobrania
  HeatTestType type;
  double? value; // progesteron
  String unit; // 'ng/ml' albo 'nmol/l'
  CytologyResult? cytology;
  String notes;

  HeatTest({
    required this.id,
    required this.date,
    required this.type,
    this.value,
    this.unit = 'ng/ml',
    this.cytology,
    this.notes = '',
  });

  /// Progesteron w ng/ml (1 ng/ml ≈ 3,18 nmol/l).
  double? get ngPerMl => value == null ? null : (unit == 'nmol/l' ? value! / 3.18 : value);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type.name,
        'value': value,
        'unit': unit,
        'cyto': cytology?.name,
        'notes': notes,
      };

  factory HeatTest.fromJson(Map<String, dynamic> j) => HeatTest(
        id: j['id'] ?? '${j['date']}',
        date: DateTime.parse(j['date']),
        type: HeatTestType.values.asNameMap()[j['type']] ?? HeatTestType.progesterone,
        value: (j['value'] as num?)?.toDouble(),
        unit: j['unit'] == 'nmol/l' ? 'nmol/l' : 'ng/ml',
        cytology: CytologyResult.values.asNameMap()[j['cyto']],
        notes: j['notes'] ?? '',
      );

  /// Orientacyjny opis poziomu progesteronu wg literatury (Concannon 2011).
  /// Wartości referencyjne różnią się między laboratoriami – decyduje lekarz.
  String? get progesteroneHint {
    final v = ngPerMl;
    if (type != HeatTestType.progesterone || v == null) return null;
    if (v < 2) return tr('poziom podstawowy – zwykle przed owulacją');
    if (v < 4) return tr('wzrost – zwykle okolice piku LH');
    if (v <= 10) return tr('zakres typowy dla okolic owulacji');
    return tr('wysoki – zwykle po owulacji');
  }
}

/// Komentarz do serii wyników progesteronu (nie diagnoza).
///
/// Pojedynczy wynik nie potwierdza owulacji: liczy się przebieg serii
/// (zwykle co 1–3 dni) i ocena lekarza, a normy zależą od metody i laboratorium.
String? progesteroneSeriesNote(List<HeatTest> tests) {
  final p = [for (final t in tests) if (t.type == HeatTestType.progesterone && t.ngPerMl != null) t]
    ..sort((a, b) => a.date.compareTo(b.date));
  if (p.isEmpty) return null;
  if (p.length == 1) {
    return tr('Jeden wynik nie potwierdza owulacji. Potrzebna jest seria badań (zwykle co 1–3 dni), którą ocenia lekarz weterynarii.');
  }
  final first = p.first.ngPerMl!, last = p.last.ngPerMl!;
  if (last > first && last >= 4 && first < 4) {
    return tr('W serii widać wzrost progesteronu. Czy i kiedy nastąpiła owulacja, ustala lekarz weterynarii – aplikacja nie wpisuje jej sama.');
  }
  if (last <= first) {
    return tr('W serii nie widać wzrostu. Kolejne badania i ich ocenę zaplanuj z lekarzem weterynarii.');
  }
  return tr('Seria w toku. Wynik ocenia lekarz weterynarii na podstawie całej serii.');
}

/// Jedna cieczka (początek = pierwszy dzień krwawienia/obrzęku).
class HeatCycle {
  final String id;
  DateTime start;
  DateTime? end;
  String notes;

  /// Zaobserwowane objawy (klucze z [heatSymptoms]).
  List<String> symptoms;

  /// Dzień, od którego suka przyjmuje psa (obserwacja opiekuna).
  DateTime? standingFrom;

  /// Data owulacji potwierdzona przez lekarza weterynarii.
  DateTime? ovulation;

  List<HeatTest> tests;

  HeatCycle({
    required this.id,
    required this.start,
    this.end,
    this.notes = '',
    List<String>? symptoms,
    this.standingFrom,
    this.ovulation,
    List<HeatTest>? tests,
  })  : symptoms = symptoms ?? [],
        tests = tests ?? [];

  int? get lengthDays => end == null ? null : _day(end!).difference(_day(start)).inCalDays + 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'notes': notes,
        if (symptoms.isNotEmpty) 'symptoms': symptoms,
        if (standingFrom != null) 'standing': standingFrom!.toIso8601String(),
        if (ovulation != null) 'ovulation': ovulation!.toIso8601String(),
        if (tests.isNotEmpty) 'tests': tests.map((t) => t.toJson()).toList(),
      };

  factory HeatCycle.fromJson(Map<String, dynamic> j) => HeatCycle(
        id: j['id'],
        start: DateTime.parse(j['start']),
        end: j['end'] == null ? null : DateTime.parse(j['end']),
        notes: j['notes'] ?? '',
        symptoms: [for (final s in (j['symptoms'] as List? ?? const [])) if (s is String) s],
        standingFrom: _date(j['standing']),
        ovulation: _date(j['ovulation']),
        tests: [
          for (final t in (j['tests'] as List? ?? const []))
            if (t is Map<String, dynamic>) HeatTest.fromJson(t)
        ]..sort((a, b) => a.date.compareTo(b.date)),
      );
}

/// Etapy cyklu płciowego suki. Z samego kalendarza nie da się ich pewnie
/// rozróżnić – faza w trakcie cieczki jest pokazywana jako potwierdzona tylko
/// na podstawie owulacji, cytologii albo obserwacji (suka przyjmuje psa).
enum HeatStage {
  proestrus('Proestrus (początek cieczki)', 'Krwawienie i obrzęk sromu. Suka zwykle przyciąga psy, ale ich nie przyjmuje. Trwa średnio ok. 9 dni (zwykle 3–17).',
      Color(0xFFFF6B6B)),
  estrus('Estrus (ruja)', 'Suka przyjmuje psa, wydzielina często jaśnieje. W tej fazie dochodzi do owulacji. Moment płodny wyznacza lekarz na podstawie badań.',
      Color(0xFFFF453A)),
  heat('Cieczka trwa', 'Proestrus i estrus trudno rozróżnić bez badań. Suka może być płodna przez całą cieczkę – pilnuj jej na spacerach.',
      Color(0xFFFF6B6B)),
  diestrus('Diestrus (po cieczce)', 'Ok. 2 miesięcy po rui (szacunkowo). Możliwa ciąża urojona: obserwuj apetyt, sutki i zachowanie.',
      Color(0xFFBF5AF2)),
  anestrus('Anestrus (spoczynek)', 'Okres bez cieczki (szacunkowo). Każda suka ma własny rytm – obserwuj pierwsze objawy kolejnej cieczki.', Color(0xFF34C759)),
  unknown('Brak danych', 'Zapisz początek cieczki, a pokażę orientacyjny etap cyklu i kolejny termin.', Color(0xFF8E8E93));

  final String _label;
  String get label => tr(_label);
  final String _description;
  String get description => tr(_description);
  final Color color;
  const HeatStage(this._label, this._description, this.color);

  bool get inHeat => this == proestrus || this == estrus || this == heat;
}

/// Skąd wiemy, w jakiej fazie jest suka.
enum StageSource { ovulation, cytology, observation, calendar }

class HeatStatus {
  final HeatStage stage;
  final StageSource source;
  final HeatCycle? current; // trwająca cieczka
  final int? day; // dzień cyklu liczony od początku ostatniej cieczki (1 = pierwszy)
  final DateTime? nextStart; // orientacyjny początek kolejnej
  final int nextSpreadDays; // niepewność prognozy (± dni)
  final int intervalDays; // średni odstęp między cieczkami
  final bool intervalFromHistory;
  final int gapsUsed; // ile odstępów z historii wzięto do średniej
  final int typicalLengthDays; // średnia długość cieczki tej suki (albo 21)

  /// Okres największej płodności – tylko gdy owulację potwierdził lekarz.
  final DateTime? fertileFrom;
  final DateTime? fertileTo;
  const HeatStatus({
    required this.stage,
    this.source = StageSource.calendar,
    this.current,
    this.day,
    this.nextStart,
    this.nextSpreadDays = 30,
    required this.intervalDays,
    required this.intervalFromHistory,
    this.gapsUsed = 0,
    this.typicalLengthDays = HeatLogic.typicalLength,
    this.fertileFrom,
    this.fertileTo,
  });

  int? daysToNext(DateTime now) => nextStart == null ? null : _day(nextStart!).difference(_day(now)).inCalDays;

  /// Faza wynika tylko z kalendarza (szacunek), a nie z badań/obserwacji.
  bool get estimated => source == StageSource.calendar;
}

/// Reguły cyklu – bez AI, czysta logika na danych.
///
/// Źródła: Concannon P.W. 2011 „Reproductive cycles of the domestic bitch”
/// (Anim Reprod Sci 124:200–210); England & von Heimendahl „BSAVA Manual of
/// Canine and Feline Reproduction”. Odstęp między cieczkami: zwykle 5–12 mies.
/// (średnio ok. 7), proestrus 3–17 dni, owulacja zwykle 2 dni po piku LH,
/// oocyty dojrzewają do zapłodnienia 2–3 dni po owulacji.
class HeatLogic {
  /// Odstęp przyjmowany, gdy brak historii (ok. 6 miesięcy).
  static const defaultInterval = 182;

  /// Średnia długość cieczki używana tylko do wizualizacji, gdy brak historii.
  static const typicalLength = 21;

  /// Najdłuższa realna cieczka – po tym czasie bez zapisanego końca uznajemy ją za zakończoną.
  static const maxLength = 30;

  /// Dzień cieczki, od którego zwykle zaczyna się badania progesteronu przed planowanym kryciem.
  static const testFromDay = 5;
  static const diestrusDays = 60;

  /// Średni odstęp z historii (pomija nierealne przerwy, np. brakujące wpisy).
  static (int, bool) interval(List<HeatCycle> cycles) {
    final g = _gaps(cycles);
    if (g.isEmpty) return (defaultInterval, false);
    final recent = g.length > 4 ? g.sublist(g.length - 4) : g;
    return ((recent.reduce((a, b) => a + b) / recent.length).round(), true);
  }

  static List<int> _gaps(List<HeatCycle> cycles) {
    final starts = cycles.map((c) => _day(c.start)).toList()..sort();
    final gaps = <int>[];
    for (var i = 1; i < starts.length; i++) {
      final g = starts[i].difference(starts[i - 1]).inCalDays;
      if (g >= 100 && g <= 420) gaps.add(g);
    }
    return gaps;
  }

  /// Niepewność prognozy: odchylenie z historii (min. 14 dni), a bez historii ±30 dni.
  static int spread(List<HeatCycle> cycles) {
    final g = _gaps(cycles);
    if (g.isEmpty) return 30;
    if (g.length == 1) return 21;
    final m = g.reduce((a, b) => a + b) / g.length;
    final sd = math.sqrt(g.fold(0.0, (a, x) => a + (x - m) * (x - m)) / (g.length - 1));
    return math.max(14, sd.round());
  }

  /// Średnia długość zapisanych cieczek.
  static int averageLength(List<HeatCycle> cycles) {
    final l = [for (final c in cycles) if (c.lengthDays != null && c.lengthDays! >= 5 && c.lengthDays! <= 40) c.lengthDays!];
    if (l.isEmpty) return typicalLength;
    return (l.reduce((a, b) => a + b) / l.length).round();
  }

  static HeatStatus status(List<HeatCycle> cycles, DateTime now) {
    final (gap, fromHistory) = interval(cycles);
    if (cycles.isEmpty) {
      return HeatStatus(stage: HeatStage.unknown, intervalDays: gap, intervalFromHistory: false);
    }
    final sorted = [...cycles]..sort((a, b) => a.start.compareTo(b.start));
    final last = sorted.last;
    final today = _day(now);
    final start = _day(last.start);
    final day = today.difference(start).inCalDays + 1;
    final avgLen = averageLength(sorted);
    final ov = last.ovulation == null ? null : _day(last.ovulation!);

    // Koniec cieczki: zapisany albo – przy braku zapisu – szacunek. Po potwierdzonej
    // owulacji estrus zwykle kończy się ok. 7–8 dni później (początek diestrus).
    final DateTime heatEnd;
    if (last.end != null) {
      heatEnd = _day(last.end!);
    } else if (ov != null) {
      heatEnd = ov.plusDays(8);
    } else {
      heatEnd = start.plusDays(maxLength - 1);
    }

    HeatStage stage;
    var source = StageSource.calendar;
    if (day < 1) {
      stage = HeatStage.anestrus;
    } else if (!today.isAfter(heatEnd)) {
      final cyto = [for (final t in last.tests) if (t.type == HeatTestType.cytology && t.cytology != null && !_day(t.date).isAfter(today)) t];
      if (ov != null) {
        source = StageSource.ovulation;
        final d = today.difference(ov).inCalDays;
        stage = d < -2 ? HeatStage.proestrus : (d <= 7 ? HeatStage.estrus : HeatStage.diestrus);
      } else if (cyto.isNotEmpty && cyto.last.cytology != CytologyResult.other) {
        source = StageSource.cytology;
        stage = switch (cyto.last.cytology!) {
          CytologyResult.proestrus => HeatStage.proestrus,
          CytologyResult.estrus => HeatStage.estrus,
          _ => HeatStage.diestrus,
        };
      } else if (last.standingFrom != null && !today.isBefore(_day(last.standingFrom!))) {
        source = StageSource.observation;
        stage = HeatStage.estrus;
      } else {
        stage = HeatStage.heat;
      }
    } else if (today.difference(heatEnd).inCalDays <= diestrusDays) {
      stage = HeatStage.diestrus;
    } else {
      stage = HeatStage.anestrus;
    }
    final active = stage.inHeat || (stage == HeatStage.diestrus && !today.isAfter(heatEnd));

    return HeatStatus(
      stage: stage,
      source: source,
      current: active ? last : null,
      day: day,
      nextStart: start.plusDays(gap),
      nextSpreadDays: spread(sorted),
      intervalDays: gap,
      intervalFromHistory: fromHistory,
      gapsUsed: _gaps(sorted).length,
      typicalLengthDays: avgLen,
      fertileFrom: ov,
      fertileTo: ov?.plusDays(5),
    );
  }
}

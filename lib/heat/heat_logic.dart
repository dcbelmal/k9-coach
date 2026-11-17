import 'package:material_ui/material_ui.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Jedna cieczka (początek = pierwszy dzień krwawienia/obrzęku).
class HeatCycle {
  final String id;
  DateTime start;
  DateTime? end;
  String notes;

  HeatCycle({required this.id, required this.start, this.end, this.notes = ''});

  int? get lengthDays => end == null ? null : _day(end!).difference(_day(start)).inDays + 1;

  Map<String, dynamic> toJson() =>
      {'id': id, 'start': start.toIso8601String(), 'end': end?.toIso8601String(), 'notes': notes};

  factory HeatCycle.fromJson(Map<String, dynamic> j) => HeatCycle(
        id: j['id'],
        start: DateTime.parse(j['start']),
        end: j['end'] == null ? null : DateTime.parse(j['end']),
        notes: j['notes'] ?? '',
      );
}

/// Etapy cyklu płciowego suki (wartości orientacyjne, każda suka jest inna).
enum HeatStage {
  proestrus('Początek cieczki (proestrus)', 'Krwawienie i obrzęk sromu. Suka przyciąga psy, ale jeszcze ich nie przyjmuje.',
      Color(0xFFFF6B6B)),
  estrus('Ruja (estrus) – dni płodne', 'Wydzielina jaśnieje, suka przyjmuje psa. Najwyższa płodność. Pilnuj na spacerach.',
      Color(0xFFFF453A)),
  diestrus('Po cieczce (diestrus)', 'Około 2 miesięcy po rui. Możliwa ciąża urojona: obserwuj apetyt, sutki i zachowanie.',
      Color(0xFFBF5AF2)),
  anestrus('Spoczynek (anestrus)', 'Okres bez cieczki. Dobry czas na intensywny trening i starty.', Color(0xFF34C759)),
  unknown('Brak danych', 'Zapisz początek cieczki, a policzę etap cyklu i kolejny termin.', Color(0xFF8E8E93));

  final String label;
  final String description;
  final Color color;
  const HeatStage(this.label, this.description, this.color);
}

class HeatStatus {
  final HeatStage stage;
  final HeatCycle? current; // trwająca cieczka
  final int? day; // dzień cyklu liczony od początku ostatniej cieczki (1 = pierwszy)
  final DateTime? nextStart; // przewidywany początek kolejnej
  final int intervalDays; // średni odstęp między cieczkami
  final bool intervalFromHistory;
  final DateTime? fertileFrom;
  final DateTime? fertileTo;
  const HeatStatus({
    required this.stage,
    this.current,
    this.day,
    this.nextStart,
    required this.intervalDays,
    required this.intervalFromHistory,
    this.fertileFrom,
    this.fertileTo,
  });

  int? daysToNext(DateTime now) => nextStart == null ? null : _day(nextStart!).difference(_day(now)).inDays;
}

/// Reguły cyklu – bez AI, czysta logika na danych.
class HeatLogic {
  /// Typowy odstęp gdy brak historii: ok. 6 miesięcy.
  static const defaultInterval = 182;

  /// Typowa długość cieczki, gdy użytkownik nie zapisał końca.
  static const typicalLength = 21;
  static const proestrusDays = 9;
  static const diestrusDays = 60;

  /// Średni odstęp z historii (pomija nierealne przerwy, np. brakujące wpisy).
  static (int, bool) interval(List<HeatCycle> cycles) {
    final starts = cycles.map((c) => _day(c.start)).toList()..sort();
    final gaps = <int>[];
    for (var i = 1; i < starts.length; i++) {
      final g = starts[i].difference(starts[i - 1]).inDays;
      if (g >= 100 && g <= 420) gaps.add(g);
    }
    if (gaps.isEmpty) return (defaultInterval, false);
    final recent = gaps.length > 4 ? gaps.sublist(gaps.length - 4) : gaps;
    return ((recent.reduce((a, b) => a + b) / recent.length).round(), true);
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
    final day = today.difference(start).inDays + 1;
    final heatEnd = last.end != null ? _day(last.end!) : start.add(const Duration(days: typicalLength - 1));
    final fertileFrom = start.add(const Duration(days: proestrusDays));
    final fertileTo = heatEnd.isBefore(fertileFrom) ? fertileFrom : heatEnd;

    HeatStage stage;
    if (day < 1) {
      stage = HeatStage.anestrus;
    } else if (!today.isAfter(heatEnd)) {
      stage = day <= proestrusDays ? HeatStage.proestrus : HeatStage.estrus;
    } else if (today.difference(heatEnd).inDays <= diestrusDays) {
      stage = HeatStage.diestrus;
    } else {
      stage = HeatStage.anestrus;
    }
    final active = stage == HeatStage.proestrus || stage == HeatStage.estrus;

    final next = start.add(Duration(days: gap));
    return HeatStatus(
      stage: stage,
      current: active ? last : null,
      day: day,
      nextStart: next,
      intervalDays: gap,
      intervalFromHistory: fromHistory,
      fertileFrom: fertileFrom,
      fertileTo: fertileTo,
    );
  }
}

import '../date_math.dart';
import 'perf_model.dart';
import 'perf_period.dart';

/// Bilans energetyczny jednego dnia (wszystko w kcal, wszystko szacunkowe).
///
/// Bilans = spożyte − (zapotrzebowanie podstawowe + dodatkowy wydatek).
/// * Zapotrzebowanie podstawowe = plan modułu Żywienie (RER × mnożnik MER
///   wg wieku, kastracji, aktywności i celu). Mnożnik obejmuje zwykłą dzienną
///   aktywność psa (spacery, krótkie treningi).
/// * Dodatkowy wydatek = koszt ruchu tylko z wysiłku ponad zwykły dzień
///   (canicross, bikejoring, kondycja) – tak jak w module Żywienie. Koszt
///   ruchu ze spacerów pokazujemy osobno, ale nie doliczamy go drugi raz.
class DayEnergy {
  final DateTime day;

  /// Spożyte kcal (karma, przysmaki, suplementy). null = brak wpisów karmienia.
  final double? eatenKcal;

  /// Spoczynkowe zapotrzebowanie (RER) i podstawowe (MER z planu). null = brak masy.
  final double? rerKcal, baseKcal;

  /// Wysiłek ponad zwykły dzień (doliczany) i zwykła aktywność (już w podstawowym).
  final double extraKcal, routineKcal;

  const DayEnergy(this.day, {this.eatenKcal, this.rerKcal, this.baseKcal, this.extraKcal = 0, this.routineKcal = 0});

  double? get needKcal => baseKcal == null ? null : baseKcal! + extraKcal;

  /// Dodatni = nadwyżka, ujemny = niedobór. null = brak danych.
  double? get balance => eatenKcal == null || needKcal == null ? null : eatenKcal! - needKcal!;
}

/// Wydatek z treningów jednego dnia rozdzielony na dodatkowy i zwykły.
(double extra, double routine) activityKcal(Iterable<SessionMetrics> day) {
  var extra = 0.0, routine = 0.0;
  for (final m in day) {
    if (m.kcal.source == KcalSource.none) continue;
    if (m.kcal.extra) {
      extra += m.kcal.kcal;
    } else {
      routine += m.kcal.kcal;
    }
  }
  return (extra, routine);
}

/// Dni zakresu (bez przyszłych).
List<DateTime> daysIn(DateRange r, {DateTime? today}) {
  final t = today ?? DateTime.now();
  final end = DateTime(t.year, t.month, t.day + 1);
  final out = <DateTime>[];
  for (var d = r.from; d.isBefore(r.to) && d.isBefore(end); d = d.plusDays(1)) {
    out.add(d);
  }
  return out;
}

/// Podsumowanie bilansu okresu: średnie dzienne liczone tylko z dni,
/// w których są wpisy karmienia (inaczej bilans byłby fikcyjnie ujemny).
class EnergyPeriod {
  final List<DayEnergy> days;
  const EnergyPeriod(this.days);

  List<DayEnergy> get withFood => [
    for (final d in days)
      if (d.balance != null) d,
  ];

  double? _avg(Iterable<double?> v) {
    final l = [for (final x in v) ?x];
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }

  double? get avgEaten => _avg(withFood.map((d) => d.eatenKcal));
  double? get avgRer => _avg(withFood.map((d) => d.rerKcal));
  double? get avgBase => _avg(withFood.map((d) => d.baseKcal));
  double? get avgExtra => _avg(withFood.map((d) => d.extraKcal));
  double? get avgBalance => _avg(withFood.map((d) => d.balance));
  double get totalExtra => days.fold(0.0, (a, d) => a + d.extraKcal);
  double get totalRoutine => days.fold(0.0, (a, d) => a + d.routineKcal);
}

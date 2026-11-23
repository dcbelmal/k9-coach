import 'dart:math' as math;

import '../date_math.dart';
import '../models.dart';
import '../store.dart' show startOfWeek;
import 'perf_model.dart';

/// Zakres analizy.
enum PerfPeriod { session, day, week, month, year, custom }

/// Przedział [from, to) w czasie lokalnym.
class DateRange {
  final DateTime from, to;
  const DateRange(this.from, this.to);

  bool contains(DateTime d) => !d.isBefore(from) && d.isBefore(to);
  int get days => to.difference(from).inCalDays;

  @override
  bool operator ==(Object other) => other is DateRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Zakres okresu zawierającego [anchor]. Dla [PerfPeriod.custom] podaj [custom]
/// (koniec włącznie – cały dzień).
DateRange rangeFor(PerfPeriod p, DateTime anchor, {DateRange? custom}) {
  final d = _day(anchor);
  switch (p) {
    case PerfPeriod.session:
    case PerfPeriod.day:
      return DateRange(d, d.plusDays(1));
    case PerfPeriod.week:
      final s = startOfWeek(d);
      return DateRange(s, s.plusDays(7));
    case PerfPeriod.month:
      return DateRange(DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
    case PerfPeriod.year:
      return DateRange(DateTime(d.year), DateTime(d.year + 1));
    case PerfPeriod.custom:
      final c = custom ?? DateRange(d.plusDays(-29), d.plusDays(1));
      return DateRange(_day(c.from), _day(c.to));
  }
}

/// Poprzedni okres tej samej długości (do porównania).
DateRange previousRange(PerfPeriod p, DateRange r) {
  switch (p) {
    case PerfPeriod.month:
      return DateRange(DateTime(r.from.year, r.from.month - 1), r.from);
    case PerfPeriod.year:
      return DateRange(DateTime(r.from.year - 1), r.from);
    default:
      final n = math.max(1, r.days);
      return DateRange(r.from.plusDays(-n), r.from);
  }
}

/// Zmiana procentowa; null, gdy poprzednia wartość jest zerowa lub nieznana
/// (nie pokazujemy „+∞%”).
double? pctChange(double? now, double? before) {
  if (now == null || before == null || before.abs() < 1e-9) return null;
  return (now - before) / before.abs() * 100;
}

/// Rekord osobisty.
class PerfRecord {
  final double value;
  final TrainingSession session;
  const PerfRecord(this.value, this.session);
}

/// Podsumowanie okresu (albo jednego treningu).
class PerfSummary {
  final List<SessionMetrics> sessions;

  /// Pominięte duplikaty tej samej aktywności.
  final int duplicatesSkipped;
  const PerfSummary(this.sessions, {this.duplicatesSkipped = 0});

  int get count => sessions.length;
  Iterable<SessionMetrics> get _dog => sessions.where((m) => m.hasDog);

  /// Treningi z wiarygodną trasą psa.
  int get dogSessions => _dog.length;

  /// Treningi z trackerem, których dane były za słabe.
  int get insufficientSessions => sessions.where((m) => m.quality == DataQuality.insufficient).length;

  double? _sum(Iterable<double?> v) {
    double? s;
    for (final x in v) {
      if (x != null) s = (s ?? 0) + x;
    }
    return s;
  }

  double? get dogMeters => _sum(_dog.map((m) => m.dogMeters));
  double? get handlerMeters => _sum(sessions.map((m) => m.handlerMeters));

  /// Stosunek – tylko z treningów, w których znamy oba dystanse.
  double? get ratio {
    var d = 0.0, h = 0.0;
    for (final m in _dog) {
      if (m.handlerMeters != null && m.handlerMeters! >= 50) {
        d += m.dogMeters!;
        h += m.handlerMeters!;
      }
    }
    return h < 50 ? null : d / h;
  }

  /// Czas ruchu psa (s): z trackera, a w treningach bez niego – czas ruchu treningu.
  double? get movingSec => _sum(sessions.map((m) => m.movingSec));
  double? get dogMovingSec => _sum(_dog.map((m) => m.movingSec));
  double? get restSec => _sum(_dog.map((m) => m.restSec));
  double? get noDataSec => _sum(_dog.map((m) => m.noDataSec));

  /// Średnia prędkość psa w ruchu: dystans w ruchu / czas w ruchu (ważona).
  double? get avgSpeedMs {
    var m = 0.0, t = 0.0;
    for (final s in _dog) {
      m += s.zoneMeters[1] + s.zoneMeters[2] + s.zoneMeters[3];
      t += s.movingSec ?? 0;
    }
    return t <= 0 ? null : m / t;
  }

  double? get maxSpeedMs {
    double? v;
    for (final s in _dog) {
      if (s.maxSpeedMs != null) v = math.max(v ?? 0, s.maxSpeedMs!);
    }
    return v;
  }

  List<double> get zoneSec {
    final z = [0.0, 0.0, 0.0, 0.0];
    for (final s in _dog) {
      for (var i = 0; i < 4; i++) {
        z[i] += s.zoneSec[i];
      }
    }
    return z;
  }

  /// Intensywność: część czasu z pomiarami w strefie umiarkowanej i wysokiej.
  double? get intensityShare {
    final z = zoneSec;
    final total = z.fold(0.0, (a, b) => a + b);
    return total <= 0 ? null : (z[2] + z[3]) / total;
  }

  double get load => sessions.fold(0.0, (a, m) => a + m.load);

  /// Szacowane kalorie ruchu (wszystkie treningi z szacunkiem).
  double? get kcal => _sum(sessions.where((m) => m.kcal.source != KcalSource.none).map((m) => m.kcal.kcal));

  /// Tylko wysiłek ponad zwykłą dzienną aktywność (do bilansu).
  double? get extraKcal =>
      _sum(sessions.where((m) => m.kcal.source != KcalSource.none && m.kcal.extra).map((m) => m.kcal.kcal));

  /// Treningi, w których kalorie liczono z dystansu przewodnika.
  int get kcalFromHandler => sessions.where((m) => m.kcal.source == KcalSource.handlerDistance).length;

  /// Jakość danych okresu: udział treningów z trackerem o dobrej jakości,
  /// ważony czasem. null = brak treningów z trackerem.
  DataQuality get quality {
    final tracked = sessions.where((m) => m.quality != DataQuality.none).toList();
    if (tracked.isEmpty) return DataQuality.none;
    if (tracked.every((m) => m.quality == DataQuality.insufficient)) return DataQuality.insufficient;
    if (tracked.every((m) => m.quality == DataQuality.good)) return DataQuality.good;
    return DataQuality.partial;
  }

  /// Średnie pokrycie pomiarami (0–1) treningów z trackerem.
  double? get coverage {
    final t = sessions.where((m) => m.quality != DataQuality.none).toList();
    if (t.isEmpty) return null;
    return t.fold(0.0, (a, m) => a + m.coverage) / t.length;
  }

  PerfRecord? _best(double? Function(SessionMetrics) f) {
    PerfRecord? best;
    for (final m in sessions) {
      final v = f(m);
      if (v != null && v > 0 && (best == null || v > best.value)) best = PerfRecord(v, m.session);
    }
    return best;
  }

  PerfRecord? get longestDog => _best((m) => m.dogMeters);
  PerfRecord? get fastestDog => _best((m) => m.maxSpeedMs);
  PerfRecord? get longestMoving => _best((m) => m.hasDog ? m.movingSec : null);
  PerfRecord? get fastestAvg => _best((m) => (m.dogMeters ?? 0) >= 1000 ? m.avgSpeedMs : null);
  PerfRecord? get highestLoad => _best((m) => m.load);
}

/// Wybór treningów do analizy: wykonane, w zakresie, wybrane dyscypliny
/// (puste = wszystkie), bez duplikatów.
(List<TrainingSession>, int) selectSessions(
  Iterable<TrainingSession> all,
  DateRange r, {
  Set<Discipline> only = const {},
}) {
  final inRange = all.where((t) => t.done && r.contains(t.date) && (only.isEmpty || only.contains(t.discipline)));
  return dedupeSessions(inRange.toList());
}

/// Punkt trendu (początek przedziału, podsumowanie).
typedef TrendPoint = (DateTime, PerfSummary);

/// Podział okresu na przedziały do wykresu trendu: dni (do 31 dni),
/// tygodnie (do ok. pół roku), miesiące (dłużej).
List<TrendPoint> trend(List<SessionMetrics> metrics, DateRange r) {
  final days = r.days;
  final out = <TrendPoint>[];
  DateTime next(DateTime d) => days <= 31
      ? d.plusDays(1)
      : days <= 190
      ? d.plusDays(7)
      : DateTime(d.year, d.month + 1);
  var start = days <= 31 ? r.from : (days <= 190 ? startOfWeek(r.from) : DateTime(r.from.year, r.from.month));
  while (start.isBefore(r.to)) {
    final end = next(start);
    final b = DateRange(start, end);
    out.add((
      start,
      PerfSummary([
        for (final m in metrics)
          if (b.contains(m.session.date)) m,
      ]),
    ));
    start = end;
  }
  return out;
}

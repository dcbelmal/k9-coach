import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'track.dart';

const _d = Distance();

/// Najwyższa wiarygodna prędkość psa (m/s) – jak w filtrze pomiarów.
const _maxSpeed = 18.0;

/// Pies „aktywny” powyżej tej prędkości (m/s), poniżej – odpoczynek.
const activeSpeedMs = 0.6;

/// Pozycja na trasie w chwili [t] (interpolacja liniowa w obrębie segmentu).
/// null, gdy w tej chwili nie ma pomiarów (przerwa, pauza) albo najbliższe
/// pomiary są dalej niż [maxGapSec].
LatLng? positionAt(List<List<TrackPoint>> segments, double t, {double maxGapSec = 30}) {
  for (final s in segments) {
    if (s.isEmpty || t < s.first.t || t > s.last.t) continue;
    for (var i = 1; i < s.length; i++) {
      final a = s[i - 1], b = s[i];
      if (t < a.t || t > b.t) continue;
      final dt = b.t - a.t;
      if (dt > maxGapSec * 2) return null;
      final f = dt <= 0 ? 0.0 : (t - a.t) / dt;
      return LatLng(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f);
    }
    if (s.length == 1 && (s.first.t - t).abs() <= maxGapSec) return s.first.ll;
  }
  return null;
}

/// Odcinek trasy psa między dwoma pomiarami – do mapy intensywności.
class DogLeg {
  final TrackPoint a, b;
  final double speedMs;
  const DogLeg(this.a, this.b, this.speedMs);
}

/// Odcinki psa z prędkością (bez przerw i niemożliwych skoków).
List<DogLeg> dogLegs(Track t) => [
      for (final s in t.dogSegments)
        for (var i = 1; i < s.length; i++)
          if (s[i].t - s[i - 1].t > 0 && s[i].t - s[i - 1].t <= 120)
            if (_d(s[i - 1].ll, s[i].ll) / (s[i].t - s[i - 1].t) <= _maxSpeed)
              DogLeg(s[i - 1], s[i], _d(s[i - 1].ll, s[i].ll) / (s[i].t - s[i - 1].t)),
    ];

/// Przedział intensywności: 0 = stęp/postój, 1 = kłus, 2 = galop, 3 = sprint.
int intensityBand(double speedMs) => speedMs < 1.5
    ? 0
    : speedMs < 4
        ? 1
        : speedMs < 7
            ? 2
            : 3;

/// Statystyki psa z jednego treningu (z obroży GPS).
class DogStats {
  final double dogMeters, handlerMeters;
  final double? avgSpeedMs, maxSpeedMs;
  final double? avgFromHandlerM, maxFromHandlerM;
  final double activeSec, restSec;

  /// (czas ruchu, prędkość m/s) – do wykresu.
  final List<(double, double)> speedSeries;

  /// (czas ruchu, odległość od przewodnika m) – do wykresu.
  final List<(double, double)> distanceSeries;
  final int points;
  final double? medianIntervalSec;

  /// Część treningu pokryta pomiarami psa (0–1).
  final double coverage;

  /// Powody niskiej wiarygodności (pusta lista = dane wiarygodne).
  final List<DogStatsIssue> issues;

  const DogStats({
    required this.dogMeters,
    required this.handlerMeters,
    this.avgSpeedMs,
    this.maxSpeedMs,
    this.avgFromHandlerM,
    this.maxFromHandlerM,
    required this.activeSec,
    required this.restSec,
    required this.speedSeries,
    required this.distanceSeries,
    required this.points,
    this.medianIntervalSec,
    required this.coverage,
    required this.issues,
  });

  bool get reliable => issues.isEmpty;

  /// Ile razy dłuższą trasę zrobił pies niż przewodnik.
  double? get ratio => handlerMeters < 50 ? null : dogMeters / handlerMeters;

  static DogStats of(Track t) {
    final legs = dogLegs(t);
    var active = 0.0, rest = 0.0;
    double? maxSpeed;
    final speeds = <(double, double)>[];
    final dts = <double>[];
    for (final l in legs) {
      final dt = l.b.t - l.a.t;
      dts.add(dt);
      if (l.speedMs >= activeSpeedMs) {
        active += dt;
      } else {
        rest += dt;
      }
      // Maksimum tylko z odcinków ≥ 3 s – krótsze to głównie szum GPS.
      if (dt >= 3) maxSpeed = math.max(maxSpeed ?? 0, l.speedMs);
      speeds.add(((l.a.t + l.b.t) / 2, l.speedMs));
    }
    final dogSec = t.dogSeconds;
    final dogM = t.dogMeters;

    final dists = <(double, double)>[];
    for (final p in t.dog) {
      final h = positionAt(t.segments, p.t);
      if (h != null) dists.add((p.t, _d(h, p.ll)));
    }
    double? avgFrom, maxFrom;
    if (dists.isNotEmpty) {
      avgFrom = dists.fold<double>(0, (a, e) => a + e.$2) / dists.length;
      maxFrom = dists.map((e) => e.$2).reduce(math.max);
    }

    dts.sort();
    final median = dts.isEmpty ? null : dts[dts.length ~/ 2];
    final pts = t.dog.length;
    final total = t.points.isEmpty ? 0.0 : t.points.last.t - t.points.first.t;
    final coverage = total <= 0 ? (dogSec > 0 ? 1.0 : 0.0) : (dogSec / total).clamp(0.0, 1.0);
    final issues = <DogStatsIssue>[
      if (pts < 10) DogStatsIssue.fewPoints,
      if (median != null && median > 20) DogStatsIssue.sparse,
      if (coverage < 0.6) DogStatsIssue.gaps,
      if (dists.length < pts ~/ 2) DogStatsIssue.noHandler,
    ];

    return DogStats(
      dogMeters: dogM,
      handlerMeters: t.meters,
      avgSpeedMs: dogSec > 0 ? dogM / dogSec : null,
      maxSpeedMs: maxSpeed,
      avgFromHandlerM: avgFrom,
      maxFromHandlerM: maxFrom,
      activeSec: active,
      restSec: rest,
      speedSeries: speeds,
      distanceSeries: dists,
      points: pts,
      medianIntervalSec: median,
      coverage: coverage,
      issues: issues,
    );
  }
}

enum DogStatsIssue {
  /// Mniej niż 10 pomiarów psa.
  fewPoints,

  /// Pomiar rzadziej niż co 20 s – trasa uproszczona, prędkości zaniżone.
  sparse,

  /// Pomiary obejmują mniej niż 60% treningu.
  gaps,

  /// Brak trasy przewodnika w tych samych chwilach (odległość nieznana).
  noHandler,
}

/// Porównanie trasy psa ze śladem założonym wcześniej (tropienie IGP).
///
/// Orientacyjne: błąd GPS (kilka–kilkanaście metrów) jest porównywalny
/// z odchyleniami ocenianymi na próbie – nie zastępuje oceny sędziego.
class TrackingAnalysis {
  /// Odchylenie psa od śladu: średnie i największe (m).
  final double avgDevM, maxDevM;

  /// Część pomiarów psa w odległości ≤ 10 m od śladu.
  final double within10;

  /// Część śladu, przy której pies był (≤ 10 m).
  final double covered;
  final int dogPoints;
  const TrackingAnalysis(this.avgDevM, this.maxDevM, this.within10, this.covered, this.dogPoints);

  static TrackingAnalysis? compare(List<TrackPoint> laid, List<TrackPoint> dog) {
    if (laid.length < 2 || dog.isEmpty) return null;
    final devs = [for (final p in dog) distanceToPath(p.ll, laid)];
    final near = devs.where((d) => d <= 10).length;
    var cov = 0;
    for (final q in laid) {
      if (dog.any((p) => _d(q.ll, p.ll) <= 10)) cov++;
    }
    return TrackingAnalysis(
      devs.reduce((a, b) => a + b) / devs.length,
      devs.reduce(math.max),
      near / devs.length,
      cov / laid.length,
      dog.length,
    );
  }
}

/// Najmniejsza odległość punktu od łamanej (m), w lokalnym rzucie płaskim.
double distanceToPath(LatLng p, List<TrackPoint> path) {
  if (path.length == 1) return _d(p, path.first.ll);
  final k = math.cos(p.latitude * math.pi / 180);
  const m = 111195.0;
  (double, double) xy(LatLng q) => ((q.longitude - p.longitude) * m * k, (q.latitude - p.latitude) * m);
  var best = double.infinity;
  for (var i = 1; i < path.length; i++) {
    final (ax, ay) = xy(path[i - 1].ll);
    final (bx, by) = xy(path[i].ll);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var f = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    f = f.clamp(0.0, 1.0);
    final x = ax + dx * f, y = ay + dy * f;
    best = math.min(best, math.sqrt(x * x + y * y));
  }
  return best;
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Punkt trasy: pozycja + czas ruchu (sekundy od startu, bez pauz).
class TrackPoint {
  final double lat, lng;
  final double t; // sekundy ruchu
  final double? speed; // m/s z GPS
  const TrackPoint(this.lat, this.lng, this.t, [this.speed]);
  LatLng get ll => LatLng(lat, lng);
  List<num> toJson() => [
        double.parse(lat.toStringAsFixed(6)),
        double.parse(lng.toStringAsFixed(6)),
        double.parse(t.toStringAsFixed(1)),
        if (speed != null) double.parse(speed!.toStringAsFixed(2)),
      ];
  factory TrackPoint.fromJson(List<dynamic> j) => TrackPoint(
      (j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), j.length > 3 ? (j[3] as num).toDouble() : null);
}

class KmSplit {
  final int km; // numer kilometra (1, 2, …); ostatni może być niepełny
  final double meters;
  final double seconds;
  const KmSplit(this.km, this.meters, this.seconds);
  double get paceSecPerKm => meters <= 0 ? 0 : seconds / meters * 1000;
}

const _dist = Distance();

class Track {
  /// Segmenty (nowy segment po każdej pauzie, żeby nie łączyć linią).
  final List<List<TrackPoint>> segments;
  final List<double> laps; // czas ruchu w chwili okrążenia

  /// Trasa psa z obroży GPS (pusta, gdy trening bez obroży).
  final List<TrackPoint> dog;
  Track(this.segments, this.laps, [this.dog = const []]);

  bool get hasDog => dog.length > 1;

  /// Dystans psa z obroży (metry).
  double get dogMeters {
    var m = 0.0;
    for (var i = 1; i < dog.length; i++) {
      m += _dist(dog[i - 1].ll, dog[i].ll);
    }
    return m;
  }

  Iterable<TrackPoint> get points => segments.expand((s) => s);

  String encode() => jsonEncode({
        'v': 1,
        's': [for (final s in segments) [for (final p in s) p.toJson()]],
        'laps': laps,
        if (dog.isNotEmpty) 'dog': [for (final p in dog) p.toJson()],
      });

  factory Track.decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return Track([
      for (final s in j['s'] as List) [for (final p in s as List) TrackPoint.fromJson(p as List)]
    ], [for (final l in (j['laps'] as List? ?? [])) (l as num).toDouble()],
        [for (final p in (j['dog'] as List? ?? [])) TrackPoint.fromJson(p as List)]);
  }

  double get meters {
    var m = 0.0;
    for (final s in segments) {
      for (var i = 1; i < s.length; i++) {
        m += _dist(s[i - 1].ll, s[i].ll);
      }
    }
    return m;
  }

  /// Podział na kilometry (interpolacja w punkcie przekroczenia każdego km).
  List<KmSplit> splits() {
    final out = <KmSplit>[];
    var acc = 0.0, kmStartT = 0.0, kmStartM = 0.0;
    var nextKm = 1000.0;
    for (final s in segments) {
      for (var i = 1; i < s.length; i++) {
        final d = _dist(s[i - 1].ll, s[i].ll);
        final dt = s[i].t - s[i - 1].t;
        while (acc + d >= nextKm && d > 0) {
          final f = (nextKm - acc) / d;
          final tCross = s[i - 1].t + dt * f;
          out.add(KmSplit(out.length + 1, 1000, tCross - kmStartT));
          kmStartT = tCross;
          kmStartM = nextKm;
          nextKm += 1000;
        }
        acc += d;
      }
    }
    final last = points.isEmpty ? 0.0 : points.last.t;
    if (acc - kmStartM > 50) out.add(KmSplit(out.length + 1, acc - kmStartM, last - kmStartT));
    return out;
  }

  /// Najwyższa wiarygodna prędkość psa z człowiekiem/rowerem w zapisie GPS.
  static const maxPlausibleKmh = 50.0;

  /// Seria prędkości (km/h) co ~[step] sekund, wygładzona – do wykresu.
  List<(double, double)> speedSeries({double step = 15}) {
    final res = <(double, double)>[];
    for (final s in segments) {
      if (s.length < 2) continue;
      var a = 0;
      for (var b = 1; b < s.length; b++) {
        if (s[b].t - s[a].t >= step || b == s.length - 1) {
          var m = 0.0;
          for (var k = a + 1; k <= b; k++) {
            m += _dist(s[k - 1].ll, s[k].ll);
          }
          final dt = s[b].t - s[a].t;
          // Krótkie okno na końcu segmentu (kilka sekund) daje zawyżone prędkości z szumu GPS.
          // Okna szybsze niż [maxPlausibleKmh] to błąd GPS – pomijamy je zamiast
          // przycinać, żeby nie pokazywać fałszywej „prędkości maksymalnej”.
          final v = dt > 0 ? m / dt * 3.6 : 0.0;
          if (dt >= step / 2 && v <= maxPlausibleKmh) res.add((s[b].t, v));
          a = b;
        }
      }
    }
    return res;
  }

  double maxSpeedKmh() {
    final s = speedSeries(step: 10);
    return s.isEmpty ? 0 : s.map((e) => e.$2).reduce(math.max);
  }
}

String fmtPace(double secPerKm) {
  if (secPerKm <= 0 || secPerKm.isInfinite || secPerKm.isNaN || secPerKm > 3600) return '–:––';
  final m = secPerKm ~/ 60, s = (secPerKm % 60).round();
  return s == 60 ? '${m + 1}:00' : '$m:${s.toString().padLeft(2, '0')}';
}

String fmtClock(double sec) {
  final t = sec.round();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

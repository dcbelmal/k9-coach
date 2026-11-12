import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'track.dart';

/// Przykładowa trasa (pętla w lesie) do trybu demo.
Track demoTrack(double km, double paceSecPerKm, math.Random rnd, {double lat = 54.41, double lng = 18.56}) {
  final total = km * 1000;
  final rot = rnd.nextDouble() * math.pi;
  const n = 400;
  List<LatLng> shape(double r) {
    final rLat = r / 111320, rLng = r / (111320 * math.cos(lat * math.pi / 180));
    return [
      for (var i = 0; i <= n; i++)
        () {
          final a = rot + 2 * math.pi * i / n;
          final wob = 1 + 0.18 * math.sin(a * 3 + rot) + 0.07 * math.sin(a * 7);
          return LatLng(lat + rLat * math.sin(a) * wob * 0.8, lng + rLng * math.cos(a) * wob * 1.2);
        }()
    ];
  }

  const dist = Distance();
  double len(List<LatLng> p) {
    var m = 0.0;
    for (var i = 1; i < p.length; i++) {
      m += dist(p[i - 1], p[i]);
    }
    return m;
  }

  final r0 = total / (2 * math.pi);
  final pts = shape(r0 * total / len(shape(r0)));
  final out = <TrackPoint>[];
  var t = 0.0, m = 0.0;
  for (var i = 0; i < pts.length; i++) {
    if (i > 0) {
      final d = dist(pts[i - 1], pts[i]);
      m += d;
      // Tempo: szybciej na początku, wolniej w drugiej połowie.
      final phase = m / total;
      final pace =
          paceSecPerKm * (0.94 + 0.12 * phase + 0.05 * math.sin(phase * 9) + (rnd.nextDouble() - 0.5) * 0.08);
      t += d / 1000 * pace;
    }
    out.add(TrackPoint(pts[i].latitude, pts[i].longitude, t));
  }
  return Track([out], const []);
}

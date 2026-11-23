import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../theme.dart';

/// Zakres radaru (m): najmniejszy, w którym mieści się pies.
double radarRange(double distM) {
  const steps = [25.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
  for (final s in steps) {
    if (distM <= s * 0.9) return s;
  }
  return steps.last;
}

/// Radar poszukiwania: przewodnik w środku, pies w kierunku i odległości
/// względem północy (góra = północ – aplikacja nie używa kompasu telefonu).
class DogRadar extends StatelessWidget {
  /// Odległość (m) i kierunek (stopnie od północy) do psa; null = nieznane.
  final double? distM, bearingDeg;

  /// Kierunek marszu przewodnika (z GPS, gdy idzie) i ruchu psa.
  final double? myCourseDeg, dogCourseDeg;

  /// Pozycja psa na żywo (false = ostatnia znana, rysowana na szaro).
  final bool live;

  const DogRadar({super.key, this.distM, this.bearingDeg, this.myCourseDeg, this.dogCourseDeg, this.live = true});

  @override
  Widget build(BuildContext context) {
    final range = distM == null ? 100.0 : radarRange(distM!);
    return LayoutBuilder(builder: (context, c) {
      final size = math.min(c.maxWidth, c.maxHeight);
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RadarPainter(
              range: range,
              distM: distM,
              bearingDeg: bearingDeg,
              myCourseDeg: myCourseDeg,
              dogCourseDeg: dogCourseDeg,
              live: live,
              rangeLabel: range >= 1000 ? '${fmtKm(range / 1000)} km' : '${range.round()} m',
              north: tr('PN'),
            ),
          ),
        ),
      );
    });
  }
}

class _RadarPainter extends CustomPainter {
  final double range;
  final double? distM, bearingDeg, myCourseDeg, dogCourseDeg;
  final bool live;
  final String rangeLabel, north;
  _RadarPainter({
    required this.range,
    this.distM,
    this.bearingDeg,
    this.myCourseDeg,
    this.dogCourseDeg,
    required this.live,
    required this.rangeLabel,
    required this.north,
  });

  Offset _at(Offset c, double r, double deg) {
    final a = (deg - 90) * math.pi / 180;
    return c + Offset(math.cos(a) * r, math.sin(a) * r);
  }

  void _text(Canvas canvas, String s, Offset at, {double size = 11, Color color = K9.muted}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 18;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = K9.faint.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawCircle(c, r, Paint()..color = K9.card);
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(c, r * f, ring);
    }
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), ring);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), ring);
    _text(canvas, north, c - Offset(0, r + 10), color: K9.orange, size: 12);
    _text(canvas, rangeLabel, c + Offset(r * 0.72, r * 0.72 + 6));

    // Kierunek marszu przewodnika.
    final my = myCourseDeg;
    if (my != null) {
      canvas.drawLine(
        c,
        _at(c, r * 0.35, my),
        Paint()
          ..color = K9.orange.withValues(alpha: 0.7)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(c, 7, Paint()..color = K9.orange);
    canvas.drawCircle(
        c,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 2);

    final d = distM, b = bearingDeg;
    if (d == null || b == null) return;
    final col = live ? K9.blue : K9.muted;
    final p = _at(c, (d / range).clamp(0.0, 1.0) * r, b);
    canvas.drawLine(
      c,
      p,
      Paint()
        ..color = col.withValues(alpha: 0.5)
        ..strokeWidth = 2,
    );
    final dc = dogCourseDeg;
    if (dc != null && live) {
      canvas.drawLine(
        p,
        _at(p, 22, dc),
        Paint()
          ..color = col
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(p, 11, Paint()..color = col);
    canvas.drawCircle(
        p,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_RadarPainter o) =>
      o.distM != distM ||
      o.bearingDeg != bearingDeg ||
      o.myCourseDeg != myCourseDeg ||
      o.dogCourseDeg != dogCourseDeg ||
      o.live != live ||
      o.range != range;
}

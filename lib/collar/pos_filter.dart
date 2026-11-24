import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Adaptacyjny filtr Kalmana pozycji (model stałej prędkości, osobno oś
/// wschód–zachód i północ–południe, w metrach od punktu odniesienia).
///
/// Po co: pojedynczy pomiar GPS ma błąd kilku metrów, a dwa takie błędy
/// (telefon i tracker) sumują się w odległości. Filtr uśrednia pomiary,
/// ufając bardziej tym z mniejszym błędem ([accuracyM]), ale:
/// * na postoju (prędkość z odbiornika < 0,5 m/s) zeruje prędkość i mocno
///   tłumi dryf;
/// * w ruchu dopuszcza szybkie zmiany, a przy nagłym skręcie / zrywie
///   (pomiar daleko poza przewidywaniem) zwiększa szum procesu, więc
///   pozycja „dogania” psa w 1–2 pomiarach zamiast się wlec.
///
/// Wynik służy tylko do wyświetlania pozycji i odległości. Trasa i dystans
/// liczą się z surowych pomiarów – filtr niczego nie dopisuje.
class PosFilter {
  /// Przyspieszenie (m/s²) przyjmowane w ruchu i na postoju.
  static const qMove = 1.5, qStill = 0.05, qManeuver = 6.0;

  /// Błąd pomiaru przyjmowany, gdy odbiornik go nie podaje (m).
  static const defaultAccM = 8.0;

  /// Po takiej przerwie (s) zaczynamy od nowa.
  static const resetAfterSec = 60.0;

  LatLng? _origin;
  DateTime? _t;
  // Stan osi: pozycja, prędkość; kowariancja 2×2 (p00, p01, p11).
  final _ax = _Axis(), _ay = _Axis();

  /// Ostatnia przefiltrowana pozycja i jej szacowany błąd (m, 1σ).
  LatLng? position;
  double? accuracyM;
  DateTime? at;

  bool get ready => position != null;

  void reset() {
    _origin = null;
    _t = null;
    position = null;
    accuracyM = null;
    at = null;
  }

  /// Dodaje pomiar. [speedMs] – prędkość z odbiornika (null = nieznana).
  /// Zwraca przefiltrowaną pozycję.
  LatLng update(LatLng p, DateTime t, {double? accuracyM, double? speedMs}) {
    final r = math.max(1.0, accuracyM ?? defaultAccM);
    final prev = _t;
    if (_origin == null || prev == null || t.difference(prev).inMilliseconds / 1000 > resetAfterSec || t.isBefore(prev)) {
      _origin = p;
      _ax.init(0, r);
      _ay.init(0, r);
      _t = t;
      return _out(t);
    }
    final dt = t.difference(prev).inMilliseconds / 1000;
    final (mx, my) = _xy(p);
    final still = speedMs != null && speedMs < 0.5;
    var q = still ? qStill : qMove;
    // Wykrycie manewru: pomiar daleko od przewidywania → większy szum procesu.
    final px = _ax.predicted(dt), py = _ay.predicted(dt);
    final innov = math.sqrt(math.pow(mx - px, 2) + math.pow(my - py, 2));
    final spread = math.sqrt(_ax.p00 + _ay.p00 + 2 * r * r);
    if (!still && innov > 3 * spread) q = qManeuver;
    _ax.step(dt, q, mx, r, zeroVelocity: still);
    _ay.step(dt, q, my, r, zeroVelocity: still);
    _t = t;
    return _out(t);
  }

  static const _m = 111195.0;

  (double, double) _xy(LatLng p) {
    final o = _origin!;
    final k = math.cos(o.latitude * math.pi / 180);
    return ((p.longitude - o.longitude) * _m * k, (p.latitude - o.latitude) * _m);
  }

  LatLng _out(DateTime t) {
    final o = _origin!;
    final k = math.cos(o.latitude * math.pi / 180);
    position = LatLng(o.latitude + _ay.x / _m, o.longitude + _ax.x / (_m * k));
    accuracyM = math.sqrt((_ax.p00 + _ay.p00) / 2);
    at = t;
    return position!;
  }
}

class _Axis {
  double x = 0, v = 0, p00 = 1, p01 = 0, p11 = 1;

  void init(double pos, double r) {
    x = pos;
    v = 0;
    p00 = r * r;
    p01 = 0;
    p11 = 4; // prędkość nieznana: ±2 m/s
  }

  double predicted(double dt) => x + v * dt;

  void step(double dt, double q, double z, double r, {bool zeroVelocity = false}) {
    // Predykcja.
    x += v * dt;
    final dt2 = dt * dt, dt3 = dt2 * dt, dt4 = dt3 * dt;
    final q2 = q * q;
    p00 += 2 * dt * p01 + dt2 * p11 + q2 * dt4 / 4;
    p01 += dt * p11 + q2 * dt3 / 2;
    p11 += q2 * dt2;
    if (zeroVelocity) {
      // Odbiornik mówi „stoję”: prędkość 0 z małą niepewnością.
      v = 0;
      p01 = 0;
      p11 = 0.04;
    }
    // Korekta pomiarem pozycji.
    final s = p00 + r * r;
    final k0 = p00 / s, k1 = p01 / s;
    final y = z - x;
    x += k0 * y;
    v += k1 * y;
    final n00 = (1 - k0) * p00;
    final n01 = (1 - k0) * p01;
    final n11 = p11 - k1 * p01;
    p00 = n00;
    p01 = n01;
    p11 = n11;
  }
}

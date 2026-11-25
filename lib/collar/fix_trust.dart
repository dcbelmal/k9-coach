import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';

/// Wynik oceny jednego pomiaru.
enum TrustEvent {
  /// Pomiar spójny z poprzednim – seria rośnie.
  ok,

  /// Pierwszy pomiar albo pierwszy po przerwie / resecie – seria od nowa.
  start,

  /// Skok pozycji niemożliwy fizycznie – seria od nowa od tego pomiaru.
  jump,

  /// Pomiar za słaby (dokładność, HDOP, satelity) – seria wyzerowana.
  weak,
}

/// Stabilizacja pozycji GPS: czy pozycji jednego urządzenia (telefonu albo
/// trackera) można już ufać.
///
/// Pojedynczy pomiar nie wystarcza, nawet z dobrą deklarowaną dokładnością
/// (np. tuż po wyjściu z budynku GPS podaje pewnie złe miejsce). Pozycja
/// jest wiarygodna dopiero po serii [need] kolejnych pomiarów, które:
/// * są świeże i mają dobrą dokładność (oraz HDOP i satelity, gdy znane);
/// * są ze sobą spójne – przesunięcie między nimi mieści się w błędzie GPS
///   i fizycznie możliwej prędkości.
///
/// Nie ma sztywnego czasu czekania: telefon (pomiar co 1 s) stabilizuje się
/// w ~[need] s, tracker (co 5 s) w 1–2 odstępach. Seria zaczyna się od nowa
/// po uruchomieniu, połączeniu, starcie treningu ([reset]), po przerwie
/// dłuższej niż [maxGapSec] i po niemożliwym skoku.
class FixTrust {
  /// Ile spójnych pomiarów z rzędu potrzeba.
  final int need;

  /// Największa akceptowana deklarowana dokładność (m).
  final double maxAccM;

  /// Największy HDOP i najmniej satelitów (gdy urządzenie je podaje).
  final double maxHdop;
  final int minSats;

  /// Najwyższa fizycznie możliwa prędkość (m/s).
  final double maxSpeedMs;

  /// Przerwa w pomiarach (s), po której pozycję trzeba ustalić od nowa.
  final double maxGapSec;

  FixTrust({
    required this.need,
    required this.maxAccM,
    this.maxHdop = 5,
    this.minSats = 4,
    required this.maxSpeedMs,
    required this.maxGapSec,
  });

  /// Telefon: pomiar co ~1 s, człowiek z psem (do ~12 m/s).
  factory FixTrust.phone() => FixTrust(need: 3, maxAccM: 25, maxSpeedMs: 12, maxGapSec: 10);

  /// Tracker na psie: pomiar co ~5 s, pies do ~18 m/s.
  factory FixTrust.dog() => FixTrust(need: 2, maxAccM: 25, maxHdop: 5, minSats: 4, maxSpeedMs: 18, maxGapSec: 30);

  int streak = 0;
  LatLng? _lastLl;
  DateTime? _lastAt;
  double _lastAcc = 0;

  /// Dlaczego pozycja nie jest jeszcze wiarygodna (null = jest).
  String? reason = '';

  /// Licznik stabilizacji (do diagnostyki) i skoków odrzuconych przez spójność.
  int stabilizations = 0;
  int jumps = 0;
  DateTime? stableSince, unstableSince;

  /// Ile trwała ostatnia stabilizacja (s).
  double? lastStabilizeSec;

  bool get stable => streak >= need;

  /// Pozycję trzeba ustalić od nowa (start aplikacji, połączenie trackera,
  /// start treningu).
  void reset(String why, [DateTime? at]) {
    if (stable) unstableSince = at;
    streak = 0;
    _lastLl = null;
    _lastAt = null;
    reason = why;
    stableSince = null;
  }

  /// Ocenia pomiar. [hdop] / [sats] – gdy urządzenie je podaje.
  TrustEvent add(LatLng ll, DateTime at, {double? accuracyM, double? hdop, int? sats, double? speedMs}) {
    final wasStable = stable;
    final acc = (accuracyM == null || accuracyM <= 0) ? 10.0 : accuracyM;
    TrustEvent ev;
    if (accuracyM != null && accuracyM > maxAccM) {
      ev = TrustEvent.weak;
      reason = tr('słaba dokładność GPS (~{0} m)', [accuracyM.round()]);
    } else if (hdop != null && hdop > maxHdop) {
      ev = TrustEvent.weak;
      reason = tr('słaba geometria satelitów (HDOP {0})', [hdop.toStringAsFixed(1).replaceAll('.', ',')]);
    } else if (sats != null && sats > 0 && sats < minSats) {
      ev = TrustEvent.weak;
      reason = tr('za mało satelitów ({0})', [sats]);
    } else {
      final pl = _lastLl, pa = _lastAt;
      final dt = pa == null ? null : at.difference(pa).inMilliseconds / 1000;
      if (pl == null || dt == null || dt > maxGapSec || dt < 0) {
        ev = TrustEvent.start;
        reason = pl == null ? (reason == '' ? tr('pierwsze pomiary') : reason) : tr('przerwa w pomiarach ({0} s)', [dt!.round()]);
      } else {
        final d = const Distance()(pl, ll);
        // Ile mogło się przesunąć: ruch (najwyżej fizycznie możliwy) + błąd obu pomiarów.
        final v = math.min(maxSpeedMs, math.max(speedMs ?? maxSpeedMs, 0) + 2);
        final allowed = v * math.max(dt, 1) + 2 * math.max(math.max(acc, _lastAcc), 5);
        if (d > allowed) {
          ev = TrustEvent.jump;
          jumps++;
          reason = tr('skok pozycji o {0} m – ustalam od nowa', [d.round()]);
        } else {
          ev = TrustEvent.ok;
        }
      }
    }
    switch (ev) {
      case TrustEvent.weak:
        streak = 0;
        _lastLl = null;
        _lastAt = null;
      case TrustEvent.start:
      case TrustEvent.jump:
        streak = 1;
        _lastLl = ll;
        _lastAt = at;
        _lastAcc = acc;
      case TrustEvent.ok:
        streak++;
        _lastLl = ll;
        _lastAt = at;
        _lastAcc = acc;
    }
    if (!wasStable && !stable) unstableSince ??= at;
    if (stable && !wasStable) {
      stabilizations++;
      stableSince = at;
      final u = unstableSince;
      lastStabilizeSec = u == null ? null : at.difference(u).inMilliseconds / 1000;
      unstableSince = null;
      reason = null;
    } else if (!stable && wasStable) {
      stableSince = null;
      unstableSince = at;
    }
    return ev;
  }

  /// Opis stanu: null = pozycja wiarygodna.
  String? get why => stable ? null : (reason == null || reason!.isEmpty ? tr('ustalanie pozycji') : reason);
}

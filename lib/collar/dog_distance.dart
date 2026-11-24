import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import 'fix_filter.dart';
import 'pos_filter.dart';

const _d = Distance();

/// Pozycja telefonu (przewodnika) z czasem pomiaru i dokładnością, surowa
/// i – gdy jest – po filtrze ([filtered], [filteredAccM]).
class HandlerFix {
  final DateTime at;
  final double lat, lng;

  /// Dokładność GPS telefonu (m), null = nieznana.
  final double? accuracyM;

  /// Prędkość z GPS telefonu (m/s), null = nieznana.
  final double? speedMs;
  final LatLng? filtered;
  final double? filteredAccM;

  /// Odstęp (s) od najbliższego prawdziwego pomiaru telefonu. 0 = to jest
  /// pomiar; więcej = pozycja z interpolacji albo „trzymana” po pomiarze.
  final double gapSec;
  const HandlerFix(this.at, this.lat, this.lng,
      {this.accuracyM, this.speedMs, this.filtered, this.filteredAccM, this.gapSec = 0});
  LatLng get ll => LatLng(lat, lng);

  /// Pozycja do porównań: po filtrze, a bez niego surowa.
  LatLng get best => filtered ?? ll;
}

/// Historia pozycji telefonu z ostatnich minut. Pozycja psa przychodzi
/// z opóźnieniem (pomiar → wysłanie → odbiór), więc porównujemy ją z tym,
/// gdzie był telefon w chwili pomiaru psa, a nie z bieżącą pozycją.
class HandlerTrack {
  HandlerTrack._();
  static final HandlerTrack instance = HandlerTrack._();

  /// Ile historii trzymamy (s).
  static const keepSec = 600;

  /// Największa przerwa między pomiarami telefonu, w której wolno
  /// interpolować, to 2 × [maxGapSec] (s).
  static const maxGapSec = 10;

  /// Ile sekund po ostatnim pomiarze telefonu wolno jeszcze użyć tej
  /// pozycji (z niepewnością rosnącą z czasem). Telefon mierzy co ~1 s,
  /// więc dłuższa cisza znaczy, że GPS telefonu stanął – wtedy pozycja jest
  /// nieaktualna, a nie „telefon stoi w miejscu”.
  static const freshSec = 10;

  /// Gdy telefon ostatnio raportował postój (prędkość < 0,5 m/s), jego
  /// pozycję trzymamy najwyżej tyle sekund (s).
  static const holdSec = 20;

  /// Zapas na ruch, gdy pozycję „trzymamy” (m).
  static const holdPadM = 3.0;

  /// Prędkość przyjmowana, gdy telefon jej nie podaje (m/s, marsz).
  static const assumedWalkMs = 1.5;

  final _filter = PosFilter();
  final List<HandlerFix> _fixes = [];
  List<HandlerFix> get fixes => List.unmodifiable(_fixes);
  HandlerFix? get last => _fixes.isEmpty ? null : _fixes.last;

  /// Dodaje pomiar telefonu; przepuszcza go przez filtr adaptacyjny.
  void add(HandlerFix f) {
    if (_fixes.isNotEmpty && !f.at.isAfter(_fixes.last.at)) return;
    final p = _filter.update(f.ll, f.at, accuracyM: f.accuracyM, speedMs: f.speedMs);
    final acc = _filter.accuracyM;
    _fixes.add(HandlerFix(f.at, f.lat, f.lng,
        accuracyM: f.accuracyM,
        speedMs: f.speedMs,
        filtered: p,
        // Błędy GPS są skorelowane w czasie – nie ufamy uśrednieniu bardziej
        // niż połowie błędu pojedynczego pomiaru.
        filteredAccM: acc == null ? null : math.max(acc, (f.accuracyM ?? DogDistance.unknownPhoneAccM) * 0.5)));
    final cut = f.at.subtract(const Duration(seconds: keepSec));
    while (_fixes.isNotEmpty && _fixes.first.at.isBefore(cut)) {
      _fixes.removeAt(0);
    }
  }

  /// Pozycja telefonu w chwili [t] (interpolacja między pomiarami).
  /// null, gdy w okolicy [t] nie ma aktualnych pomiarów telefonu.
  /// [HandlerFix.gapSec] mówi, jak daleko w czasie jest najbliższy pomiar.
  HandlerFix? at(DateTime t) {
    if (_fixes.isEmpty) return null;
    double gap(DateTime a, DateTime b) => (a.difference(b).inMilliseconds / 1000).abs();
    // Pozycja po pomiarze [f]: niepewność rośnie z czasem (ruch telefonu).
    HandlerFix after(HandlerFix f, double g) {
      final still = f.speedMs != null && f.speedMs! < 0.5;
      if (g <= 1) return f;
      if (!still && g > freshSec) return HandlerFix(t, f.lat, f.lng, gapSec: g);
      if (still && g > holdSec) return HandlerFix(t, f.lat, f.lng, gapSec: g);
      final pad = still ? holdPadM : math.max(f.speedMs ?? assumedWalkMs, 0.5) * g;
      return HandlerFix(t, f.lat, f.lng,
          accuracyM: (f.accuracyM ?? DogDistance.unknownPhoneAccM) + pad,
          speedMs: f.speedMs,
          filtered: f.filtered,
          filteredAccM: f.filteredAccM == null ? null : f.filteredAccM! + pad,
          gapSec: g);
    }

    bool usable(HandlerFix h) => h.accuracyM != null || h.gapSec <= 1;
    HandlerFix? ok(HandlerFix h) => usable(h) ? h : null;

    final first = _fixes.first, lastF = _fixes.last;
    if (!t.isAfter(first.at)) return gap(t, first.at) <= 2 ? first : null;
    if (!t.isBefore(lastF.at)) return ok(after(lastF, gap(t, lastF.at)));
    for (var i = 1; i < _fixes.length; i++) {
      final a = _fixes[i - 1], b = _fixes[i];
      if (t.isAfter(b.at)) continue;
      final dt = gap(b.at, a.at);
      if (dt > maxGapSec * 2) {
        // Przerwa w pomiarach telefonu: tylko tuż przy pomiarze.
        final gb = gap(b.at, t);
        if (gb <= 2) return b;
        return ok(after(a, gap(t, a.at)));
      }
      final f = dt <= 0 ? 0.0 : gap(t, a.at) / dt;
      double lerp(double x, double y) => x + (y - x) * f;
      double? worse(double? x, double? y) => x == null && y == null ? null : math.max(x ?? 0, y ?? 0);
      final fa = a.filtered, fb = b.filtered;
      return HandlerFix(t, lerp(a.lat, b.lat), lerp(a.lng, b.lng),
          accuracyM: worse(a.accuracyM, b.accuracyM),
          speedMs: worse(a.speedMs, b.speedMs),
          filtered: fa == null || fb == null ? null : LatLng(lerp(fa.latitude, fb.latitude), lerp(fa.longitude, fb.longitude)),
          filteredAccM: worse(a.filteredAccM, b.filteredAccM),
          gapSec: math.min(gap(t, a.at), gap(b.at, t)));
    }
    return null;
  }

  void clear() {
    _fixes.clear();
    _filter.reset();
  }
}

/// Odległość pies–przewodnik z niepewnością.
///
/// * [matchedM] – odległość w chwili pomiaru GPS psa (pozycja telefonu z tej
///   samej chwili), po filtrze adaptacyjnym; [rawM] – to samo z surowych
///   pomiarów (do diagnostyki).
/// * [currentM] – odległość ostatniej znanej pozycji psa od bieżącej pozycji
///   telefonu. Pies mógł się od tamtej chwili przesunąć – stąd rosnąca
///   niepewność [currentUncertaintyM].
///
/// Odległość nigdy nie jest „przycinana” do długości smyczy ani zerowana na
/// podstawie sygnału Bluetooth – pokazujemy to, co wynika z GPS, z błędem.
class DogDistance {
  final double? matchedM, matchedUncertaintyM, rawM;
  final double? currentM, currentUncertaintyM;

  /// Różnica czasu między porównywanymi pozycjami telefonu i psa (s).
  final double? compareDtSec;

  /// Wiek pomiaru psa (s).
  final double ageSec;

  /// Opóźnienie pomiaru psa w chwili odbioru (s).
  final double lagSec;

  /// Wiek bieżącej pozycji telefonu (s), null = brak.
  final double? phoneAgeSec;
  const DogDistance({
    this.phoneAgeSec,
    this.matchedM,
    this.matchedUncertaintyM,
    this.rawM,
    this.currentM,
    this.currentUncertaintyM,
    this.compareDtSec,
    required this.ageSec,
    required this.lagSec,
  });

  /// Dokładność GPS psa przyjmowana, gdy tracker jej nie podaje (m).
  static const unknownDogAccM = 10.0;

  /// Dokładność GPS telefonu przyjmowana, gdy telefon jej nie podaje (m).
  static const unknownPhoneAccM = 10.0;

  /// Bieżąca pozycja telefonu starsza niż tyle sekund nie służy do
  /// „bieżącej” odległości.
  static const phoneFreshSec = 10;

  /// Nieznany czas pomiaru psa – dodatkowy zapas (m).
  static const unknownTimeM = 5.0;

  /// Dokładność z Androida to promień ~68%. Do „pies w pobliżu” bierzemy
  /// ok. 95% (× 1,6) i nie mniej niż [nearbyMinM].
  static const nearbyFactor = 1.6;
  static const nearbyMinM = 5.0;

  double? get bestM => matchedM ?? currentM;
  double? get bestUncertaintyM => matchedM != null ? matchedUncertaintyM : currentUncertaintyM;

  /// Odległość w granicach błędu pomiaru – nie da się powiedzieć więcej niż
  /// „pies w pobliżu”.
  bool get withinError {
    final m = bestM, u = bestUncertaintyM;
    if (m == null || u == null) return false;
    return m <= math.max(nearbyMinM, u * nearbyFactor);
  }

  /// Promień, w którym pies „jest w pobliżu” (m).
  double? get nearbyRadiusM => bestUncertaintyM == null ? null : math.max(nearbyMinM, bestUncertaintyM! * nearbyFactor);

  /// [dogFiltered] / [dogFilteredAccM] – pozycja psa po filtrze adaptacyjnym
  /// dla tego pomiaru (null = bez filtra, liczymy z surowej).
  static DogDistance? of(CollarFix? dog, HandlerTrack track,
      {required DateTime now, LatLng? dogFiltered, double? dogFilteredAccM}) {
    if (dog == null) return null;
    final age = math.max(0.0, dog.ageSec(now));
    final dogAcc = dog.accuracyM ?? unknownDogAccM;
    final dogBest = dogFiltered ?? dog.ll;
    final dogBestAcc = dogFiltered == null ? dogAcc : math.max(dogFilteredAccM ?? dogAcc, dogAcc * 0.5);
    final timePad = dog.timeIsFix ? 0.0 : unknownTimeM;

    double? matched, matchedUnc, raw, dt;
    final h = track.at(dog.fixAt);
    if (h != null) {
      raw = _d(h.ll, dog.ll);
      matched = _d(h.best, dogBest);
      final phoneAcc = h.filtered != null ? (h.filteredAccM ?? unknownPhoneAccM) : (h.accuracyM ?? unknownPhoneAccM);
      matchedUnc = math.sqrt(dogBestAcc * dogBestAcc + phoneAcc * phoneAcc) + timePad;
      // Prawdziwa różnica czasu: od najbliższego pomiaru telefonu, nie od
      // pozycji „trzymanej” (ta zawsze miałaby 0 s).
      dt = h.gapSec;
    }

    double? current, currentUnc, phoneAge;
    final me = track.last;
    if (me != null) phoneAge = math.max(0.0, now.difference(me.at).inMilliseconds / 1000);
    if (me != null && phoneAge! <= phoneFreshSec) {
      current = _d(me.best, dogBest);
      final phoneAcc = (me.filteredAccM ?? me.accuracyM ?? unknownPhoneAccM) +
          math.max(me.speedMs ?? HandlerTrack.assumedWalkMs, 0.5) * phoneAge;
      // Pies mógł przejść od pomiaru co najmniej tyle, ile szedł (min. 1,5 m/s).
      final v = math.max(dog.speedMs ?? 0, 1.5);
      currentUnc = math.sqrt(dogBestAcc * dogBestAcc + phoneAcc * phoneAcc) + timePad + v * age;
    }
    if (matched == null && current == null) return null;
    return DogDistance(
      matchedM: matched,
      matchedUncertaintyM: matchedUnc,
      rawM: raw,
      currentM: current,
      currentUncertaintyM: currentUnc,
      compareDtSec: dt,
      ageSec: age,
      lagSec: dog.lagSec,
      phoneAgeSec: phoneAge,
    );
  }

  /// Dlaczego odległości nie da się teraz policzyć (null = da się).
  static String? whyNot(CollarFix? dog, HandlerTrack track, {required DateTime now}) {
    if (dog == null) return tr('brak pozycji psa');
    final me = track.last;
    if (me == null) return tr('brak lokalizacji telefonu');
    if (track.at(dog.fixAt) != null) return null;
    final age = now.difference(me.at).inMilliseconds / 1000;
    if (age > phoneFreshSec) return tr('pozycja telefonu nieaktualna ({0} s)', [age.round()]);
    return null;
  }
}

/// Odległość z niepewnością do pokazania: „12 m ± 7 m”, a gdy odległość
/// mieści się w błędzie – „< 9 m”. Zaokrąglenie dopasowane do błędu, żeby
/// nie udawać dokładności, której GPS nie ma.
String fmtDistance(double m, double? uncertaintyM, {String km = 'km'}) {
  String round(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1).replaceAll('.', ',')} $km';
    final step = v >= 200 ? 10 : (v >= 50 ? 5 : 1);
    return '${(v / step).round() * step} m';
  }

  final u = uncertaintyM;
  if (u == null) return round(m);
  if (m <= u) return '< ${round(u)}';
  return '${round(m)} ± ${round(u)}';
}

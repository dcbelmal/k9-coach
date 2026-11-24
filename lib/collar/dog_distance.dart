import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'fix_filter.dart';

const _d = Distance();

/// Pozycja telefonu (przewodnika) z czasem pomiaru i dokładnością.
class HandlerFix {
  final DateTime at;
  final double lat, lng;

  /// Dokładność GPS telefonu (m), null = nieznana.
  final double? accuracyM;
  const HandlerFix(this.at, this.lat, this.lng, {this.accuracyM});
  LatLng get ll => LatLng(lat, lng);
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
  /// interpolować (s).
  static const maxGapSec = 15;

  final List<HandlerFix> _fixes = [];
  List<HandlerFix> get fixes => List.unmodifiable(_fixes);
  HandlerFix? get last => _fixes.isEmpty ? null : _fixes.last;

  void add(HandlerFix f) {
    if (_fixes.isNotEmpty && f.at.isBefore(_fixes.last.at)) return;
    _fixes.add(f);
    final cut = f.at.subtract(const Duration(seconds: keepSec));
    while (_fixes.isNotEmpty && _fixes.first.at.isBefore(cut)) {
      _fixes.removeAt(0);
    }
  }

  /// Ile sekund po ostatnim pomiarze telefonu uznajemy, że stoi w miejscu.
  /// Telefon z filtrem odległości (kilka metrów) nie podaje pozycji, gdy
  /// się nie rusza – brak nowych pomiarów zwykle znaczy postój.
  static const holdSec = 60;

  /// Zapas na ruch w granicach filtru odległości, gdy pozycję „trzymamy” (m).
  static const holdPadM = 5.0;

  /// Pozycja telefonu w chwili [t] (interpolacja między pomiarami).
  /// null, gdy w okolicy [t] nie ma pomiarów telefonu.
  HandlerFix? at(DateTime t) {
    if (_fixes.isEmpty) return null;
    double gap(DateTime a, DateTime b) => (a.difference(b).inMilliseconds / 1000).abs();
    HandlerFix hold(HandlerFix f) =>
        HandlerFix(t, f.lat, f.lng, accuracyM: (f.accuracyM ?? DogDistance.unknownPhoneAccM) + holdPadM);
    final first = _fixes.first, lastF = _fixes.last;
    if (!t.isAfter(first.at)) return gap(t, first.at) <= 5 ? first : null;
    if (!t.isBefore(lastF.at)) {
      final g = gap(t, lastF.at);
      if (g <= maxGapSec) return lastF;
      return g <= holdSec ? hold(lastF) : null;
    }
    for (var i = 1; i < _fixes.length; i++) {
      final a = _fixes[i - 1], b = _fixes[i];
      if (t.isAfter(b.at)) continue;
      final dt = gap(b.at, a.at);
      if (dt > maxGapSec * 2) {
        if (gap(b.at, t) <= 5) return b;
        return gap(t, a.at) <= holdSec ? hold(a) : null;
      }
      final f = dt <= 0 ? 0.0 : gap(t, a.at) / dt;
      double? acc;
      if (a.accuracyM != null || b.accuracyM != null) acc = math.max(a.accuracyM ?? 0, b.accuracyM ?? 0);
      return HandlerFix(t, a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f, accuracyM: acc);
    }
    return null;
  }

  void clear() => _fixes.clear();
}

/// Odległość pies–przewodnik z niepewnością.
///
/// * [matchedM] – odległość w chwili pomiaru GPS psa (pozycja telefonu z tej
///   samej chwili). To najuczciwsza liczba: obie pozycje z jednego momentu.
/// * [currentM] – odległość ostatniej znanej pozycji psa od bieżącej pozycji
///   telefonu. Pies mógł się od tamtej chwili przesunąć – stąd rosnąca
///   niepewność [currentUncertaintyM].
class DogDistance {
  final double? matchedM, matchedUncertaintyM;
  final double? currentM, currentUncertaintyM;

  /// Wiek pomiaru psa (s).
  final double ageSec;

  /// Opóźnienie pomiaru psa w chwili odbioru (s).
  final double lagSec;
  const DogDistance({
    this.matchedM,
    this.matchedUncertaintyM,
    this.currentM,
    this.currentUncertaintyM,
    required this.ageSec,
    required this.lagSec,
  });

  /// Dokładność GPS psa przyjmowana, gdy tracker jej nie podaje (m).
  static const unknownDogAccM = 10.0;

  /// Dokładność GPS telefonu przyjmowana, gdy telefon jej nie podaje (m).
  static const unknownPhoneAccM = 10.0;

  /// Nieznany czas pomiaru psa – dodatkowy zapas (m).
  static const unknownTimeM = 5.0;

  /// Najczęściej pokazywana liczba: odległość z dopasowaniem czasu, a gdy
  /// nie ma historii telefonu z tej chwili – odległość bieżąca.
  double? get bestM => matchedM ?? currentM;
  double? get bestUncertaintyM => matchedM != null ? matchedUncertaintyM : currentUncertaintyM;

  /// Odległość mniejsza niż błąd pomiaru – nie da się powiedzieć więcej niż
  /// „pies jest blisko”.
  bool get withinError => bestM != null && bestUncertaintyM != null && bestM! <= bestUncertaintyM!;

  static DogDistance? of(CollarFix? dog, HandlerTrack track, {required DateTime now}) {
    if (dog == null) return null;
    final age = math.max(0.0, dog.ageSec(now));
    final dogAcc = dog.accuracyM ?? unknownDogAccM;
    final timePad = dog.timeIsFix ? 0.0 : unknownTimeM;

    double? matched, matchedUnc;
    final h = track.at(dog.fixAt);
    if (h != null) {
      matched = _d(h.ll, dog.ll);
      final phoneAcc = h.accuracyM ?? unknownPhoneAccM;
      matchedUnc = math.sqrt(dogAcc * dogAcc + phoneAcc * phoneAcc) + timePad;
    }

    double? current, currentUnc;
    final me = track.last;
    if (me != null && now.difference(me.at).inSeconds <= 120) {
      current = _d(me.ll, dog.ll);
      final phoneAcc = me.accuracyM ?? unknownPhoneAccM;
      // Pies mógł przejść od pomiaru co najmniej tyle, ile szedł (min. 1,5 m/s).
      final v = math.max(dog.speedMs ?? 0, 1.5);
      currentUnc = math.sqrt(dogAcc * dogAcc + phoneAcc * phoneAcc) + timePad + v * age;
    }
    if (matched == null && current == null) return null;
    return DogDistance(
      matchedM: matched,
      matchedUncertaintyM: matchedUnc,
      currentM: current,
      currentUncertaintyM: currentUnc,
      ageSec: age,
      lagSec: dog.lagSec,
    );
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

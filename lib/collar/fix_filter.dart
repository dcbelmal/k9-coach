import 'package:latlong2/latlong.dart';

import 'mesh_proto.dart';

/// Pozycja psa z trackera, po sprawdzeniu jakości.
class CollarFix {
  final int node;
  final double lat, lng;

  /// Kiedy GPS trackera zmierzył pozycję (czas z pakietu albo – gdy tracker
  /// go nie podał lub ma zły zegar – chwila odbioru).
  final DateTime fixAt;

  /// Kiedy telefon odebrał pakiet.
  final DateTime receivedAt;
  final double? speedMs;
  final double? accuracyM;
  final int? sats;

  /// false = pozycja w miejscu (różnica mniejsza niż dokładność GPS) – odświeża
  /// „ostatni pomiar”, ale nie dodaje punktu ani dystansu.
  final bool moved;

  const CollarFix(this.node, this.lat, this.lng, this.fixAt,
      {DateTime? receivedAt, this.speedMs, this.accuracyM, this.sats, this.moved = true})
      : receivedAt = receivedAt ?? fixAt;

  LatLng get ll => LatLng(lat, lng);

  /// Opóźnienie pomiaru (s) w chwili odbioru.
  double get lagSec => receivedAt.difference(fixAt).inMilliseconds / 1000;

  /// Wiek pomiaru (s) względem [now].
  double ageSec(DateTime now) => now.difference(fixAt).inMilliseconds / 1000;
}

/// Powód odrzucenia pomiaru (do diagnostyki).
enum FixReject {
  /// Kanał Meshtastic zaokrągla pozycję (do ~1,5 km).
  coarse,

  /// Pomiar starszy niż [FixFilter.maxAgeSec] w chwili odbioru.
  stale,

  /// Ten sam pomiar drugi raz (np. powtórzony pakiet albo odpowiedź na zapytanie).
  duplicate,

  /// Pomiar starszy niż ostatni przyjęty (pakiety w złej kolejności).
  outOfOrder,

  /// Słaby sygnał GPS: mało satelitów, fix 2D albo duży błąd pozycji.
  weak,

  /// Niemożliwy skok pozycji (prędkość ponad [FixFilter.maxSpeedMs]).
  jump,
}

/// Wynik sprawdzenia pomiaru: przyjęty [fix] albo powód odrzucenia.
class FixVerdict {
  final CollarFix? fix;
  final FixReject? reject;
  const FixVerdict.ok(CollarFix this.fix) : reject = null;
  const FixVerdict.no(FixReject this.reject) : fix = null;
  bool get accepted => fix != null;
}

const _dist = Distance();

/// Sprawdzanie pomiarów GPS z jednego trackera.
///
/// Odrzuca pozycje zaokrąglone, nieaktualne, zduplikowane, w złej kolejności,
/// ze słabym sygnałem i niemożliwe skoki. Pozycje w miejscu (dryf GPS)
/// przyjmuje jako „bez ruchu”, żeby nie naliczać fałszywego dystansu.
class FixFilter {
  /// Pomiar starszy niż tyle sekund w chwili odbioru jest nieaktualny.
  static const maxAgeSec = 120.0;

  /// Różnica zegara trackera i telefonu, powyżej której nie ufamy czasowi
  /// z pakietu (np. tracker jeszcze bez czasu z GPS).
  static const clockSkewSec = 600.0;

  /// Najwyższa wiarygodna prędkość psa (m/s) – ok. 65 km/h.
  static const maxSpeedMs = 18.0;

  /// Minimalna liczba satelitów (gdy tracker ją podaje).
  static const minSats = 4;

  /// Największy akceptowany szacowany błąd pozycji (m).
  static const maxAccuracyM = 50.0;

  /// Przesunięcie mniejsze niż to (m) traktujemy jako postój.
  static const minMoveM = 3.0;

  final int node;
  FixFilter(this.node);

  CollarFix? _last; // ostatni przyjęty (także „bez ruchu”)
  CollarFix? _lastMoved; // ostatni, od którego liczymy przesunięcie

  CollarFix? get last => _last;

  void reset() {
    _last = null;
    _lastMoved = null;
  }

  FixVerdict check(MeshPosition p, DateTime receivedAt) {
    if (p.coarse) return const FixVerdict.no(FixReject.coarse);

    // Czas pomiaru: z pakietu, chyba że zegar trackera jest wyraźnie zły.
    var fixAt = receivedAt;
    final t = p.time;
    if (t != null) {
      final skew = receivedAt.difference(t).inMilliseconds / 1000;
      if (skew.abs() <= clockSkewSec) {
        // Pomiar „z przyszłości” o kilka sekund to różnica zegarów – przycinamy.
        fixAt = skew < 0 ? receivedAt : t;
      }
    }
    if (receivedAt.difference(fixAt).inMilliseconds / 1000 > maxAgeSec) {
      return const FixVerdict.no(FixReject.stale);
    }

    final prev = _last;
    if (prev != null) {
      final same = (prev.lat - p.lat).abs() < 1e-7 && (prev.lng - p.lng).abs() < 1e-7;
      if (t != null && fixAt == prev.fixAt && same) return const FixVerdict.no(FixReject.duplicate);
      if (t != null && fixAt.isBefore(prev.fixAt)) return const FixVerdict.no(FixReject.outOfOrder);
      if (t != null && fixAt == prev.fixAt) return const FixVerdict.no(FixReject.duplicate);
    }

    if ((p.sats != null && p.sats! > 0 && p.sats! < minSats) ||
        (p.fixType != null && p.fixType! > 0 && p.fixType! < 3) ||
        (p.accuracyM != null && p.accuracyM! > maxAccuracyM)) {
      return const FixVerdict.no(FixReject.weak);
    }

    final ref = _lastMoved;
    var moved = true;
    if (ref != null) {
      final d = _dist(ref.ll, LatLng(p.lat, p.lng));
      final dt = fixAt.difference(ref.fixAt).inMilliseconds / 1000;
      if (dt > 0 && d / dt > maxSpeedMs) return const FixVerdict.no(FixReject.jump);
      if (dt <= 0 && d > 20) return const FixVerdict.no(FixReject.jump);
      // Dryf w miejscu: przesunięcie w granicach błędu GPS.
      final acc = p.accuracyM ?? 0;
      final still = d < minMoveM || d < acc * 0.6;
      if (still && (p.speedMs == null || p.speedMs! < 1)) moved = false;
    }

    final fix = CollarFix(node, p.lat, p.lng, fixAt,
        receivedAt: receivedAt, speedMs: p.speedMs, accuracyM: p.accuracyM, sats: p.sats, moved: moved);
    _last = fix;
    if (moved) _lastMoved = fix;
    return FixVerdict.ok(fix);
  }
}

/// Liczniki do ekranu diagnostyki.
class CollarDiagnostics {
  int packets = 0;
  int positions = 0;
  int accepted = 0;
  final Map<FixReject, int> rejected = {};
  int reconnects = 0;
  String? lastError;
  DateTime? connectedAt;
  DateTime? lastPacketAt;

  /// Odstępy (s) między kolejnymi przyjętymi pomiarami psa (ostatnie 20).
  final List<double> intervals = [];

  void addInterval(double s) {
    if (s <= 0 || s > 600) return;
    intervals.add(s);
    if (intervals.length > 20) intervals.removeAt(0);
  }

  /// Rzeczywisty odstęp między pomiarami (mediana), null = za mało danych.
  double? get medianInterval {
    if (intervals.length < 2) return null;
    final s = [...intervals]..sort();
    return s[s.length ~/ 2];
  }

  void reject(FixReject r) => rejected[r] = (rejected[r] ?? 0) + 1;

  void clear() {
    packets = positions = accepted = reconnects = 0;
    rejected.clear();
    intervals.clear();
    lastError = null;
  }
}

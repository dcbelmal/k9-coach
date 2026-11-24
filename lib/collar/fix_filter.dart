import 'dart:math' as math;

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

  /// true = [fixAt] to czas pomiaru podany przez GPS trackera; false = tracker
  /// podał tylko czas wysłania albo nic (prawdziwy pomiar mógł być wcześniej).
  final bool timeIsFix;

  /// Kierunek ruchu z trackera (stopnie), HDOP i numer kolejny pozycji.
  final double? courseDeg, hdop;
  final int? seq;

  const CollarFix(this.node, this.lat, this.lng, this.fixAt,
      {DateTime? receivedAt,
      this.speedMs,
      this.accuracyM,
      this.sats,
      this.moved = true,
      this.timeIsFix = true,
      this.courseDeg,
      this.hdop,
      this.seq})
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
    var timeIsFix = false;
    final t = p.time;
    if (t != null) {
      final skew = receivedAt.difference(t).inMilliseconds / 1000;
      if (skew.abs() <= clockSkewSec) {
        // Pomiar „z przyszłości” o kilka sekund to różnica zegarów – przycinamy.
        fixAt = skew < 0 ? receivedAt : t;
        timeIsFix = p.timeIsFix;
      }
    }
    if (receivedAt.difference(fixAt).inMilliseconds / 1000 > maxAgeSec) {
      return const FixVerdict.no(FixReject.stale);
    }

    final prev = _last;
    if (prev != null) {
      final same = (prev.lat - p.lat).abs() < 1e-7 && (prev.lng - p.lng).abs() < 1e-7;
      // Ten sam numer kolejny i to samo miejsce = ten sam pakiet odczytany drugi raz.
      if (p.seq != null && p.seq == prev.seq && same) return const FixVerdict.no(FixReject.duplicate);
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
      moved = !isDrift(d, p.accuracyM, p.speedMs);
    }

    final fix = CollarFix(node, p.lat, p.lng, fixAt,
        receivedAt: receivedAt,
        speedMs: p.speedMs,
        accuracyM: p.accuracyM,
        sats: p.sats,
        moved: moved,
        timeIsFix: timeIsFix,
        courseDeg: p.courseDeg,
        hdop: p.hdop,
        seq: p.seq);
    _last = fix;
    if (moved) _lastMoved = fix;
    return FixVerdict.ok(fix);
  }

  /// Czy przesunięcie o [d] m od ostatniego punktu z ruchem to dryf GPS
  /// w miejscu. Promień dryfu = szacowany błąd pozycji (co najmniej
  /// [minMoveM], bez danych 8 m). Prędkość z trackera (m/s) rozstrzyga,
  /// gdy jest: poniżej 0,5 m/s pies stoi (do 2 × promień), od 1,5 m/s idzie.
  static bool isDrift(double d, double? accuracyM, double? speedMs) {
    final r = math.max(minMoveM, accuracyM ?? 8);
    final v = speedMs;
    if (v != null && v >= 1.5 && d >= minMoveM) return false;
    if (v != null && v < 0.5) return d < r * 2;
    return d < r;
  }
}

/// Jeden odebrany pakiet z pozycją – do diagnostyki i eksportu CSV.
class FixLogEntry {
  final DateTime receivedAt;
  final int node;

  /// Czas pomiaru GPS i czas wysłania z pakietu (null = brak w pakiecie).
  final DateTime? fixAt, sentAt;
  final double lat, lng;
  final double? accuracyM, hdop, speedMs, courseDeg;
  final int? sats, seq;

  /// Sygnał radia LoRa (dBm, SNR) – tylko pakiety, które przeszły przez radio.
  final int? loraRssi;
  final double? snr;

  /// Sygnał Bluetooth telefon–urządzenie (dBm) w chwili odbioru.
  final int? bleRssi;

  /// Dokładność GPS telefonu (m) i odległość pies–telefon w chwili pomiaru psa.
  final double? phoneAccuracyM, distanceM;

  /// Odpowiedź na zapytanie aplikacji o pozycję.
  final bool reply;

  /// „ok”, „postój” albo nazwa powodu odrzucenia.
  final String verdict;

  const FixLogEntry({
    required this.receivedAt,
    required this.node,
    this.fixAt,
    this.sentAt,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.hdop,
    this.speedMs,
    this.courseDeg,
    this.sats,
    this.seq,
    this.loraRssi,
    this.snr,
    this.bleRssi,
    this.phoneAccuracyM,
    this.distanceM,
    this.reply = false,
    required this.verdict,
  });

  /// Opóźnienie: od pomiaru GPS do odbioru w telefonie (s).
  double? get lagSec => fixAt == null ? null : receivedAt.difference(fixAt!).inMilliseconds / 1000;

  static const csvHeader = 'odebrano;pomiar_gps;wyslano;opoznienie_s;wezel;lat;lng;dokladnosc_m;hdop;satelity;'
      'seq;predkosc_m_s;kierunek;lora_rssi;snr;ble_rssi;dokladnosc_telefonu_m;odleglosc_m;odpowiedz;wynik';

  String toCsv() {
    String n(num? v, [int digits = 1]) => v == null ? '' : (v is int ? '$v' : v.toStringAsFixed(digits));
    String d(DateTime? t) => t?.toIso8601String() ?? '';
    return [
      d(receivedAt),
      d(fixAt),
      d(sentAt),
      n(lagSec),
      meshNodeId(node),
      lat.toStringAsFixed(6),
      lng.toStringAsFixed(6),
      n(accuracyM),
      n(hdop, 2),
      n(sats),
      n(seq),
      n(speedMs, 2),
      n(courseDeg, 0),
      n(loraRssi),
      n(snr),
      n(bleRssi),
      n(phoneAccuracyM),
      n(distanceM),
      reply ? '1' : '0',
      verdict,
    ].join(';');
  }
}

/// Min / średnia / max z listy liczb.
class Spread {
  final double min, avg, max;
  final int count;
  const Spread(this.min, this.avg, this.max, this.count);
  static Spread? of(Iterable<double> v) {
    if (v.isEmpty) return null;
    var lo = double.infinity, hi = -double.infinity, sum = 0.0;
    for (final x in v) {
      lo = math.min(lo, x);
      hi = math.max(hi, x);
      sum += x;
    }
    return Spread(lo, sum / v.length, hi, v.length);
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

  /// Odczyty Bluetooth (każdy odczyt kolejki wiadomości z urządzenia).
  int bleReads = 0;

  /// Zapytania aplikacji o pozycję i odpowiedzi na nie.
  int requestsSent = 0;
  int requestReplies = 0;
  DateTime? lastRequestAt;

  /// Brakujące numery kolejne pozycji psa (pakiety, które nie dotarły).
  int missingSeq = 0;
  int? _lastSeq;

  /// Sygnał Bluetooth (dBm) i kiedy go zmierzono.
  int? bleRssi;
  DateTime? bleRssiAt;

  /// Odstępy (s) między kolejnymi przyjętymi pomiarami psa (ostatnie 20).
  final List<double> intervals = [];

  /// Opóźnienia (s) od pomiaru GPS do odbioru (ostatnie 50, tylko gdy
  /// tracker podał czas pomiaru).
  final List<double> lags = [];

  /// Ostatnie pakiety z pozycją (do 600 ≈ 50 min przy pomiarze co 5 s).
  final List<FixLogEntry> log = [];
  static const logMax = 600;

  void addInterval(double s) {
    if (s <= 0 || s > 600) return;
    intervals.add(s);
    if (intervals.length > 20) intervals.removeAt(0);
  }

  void addLag(double s) {
    if (s < 0 || s > 600) return;
    lags.add(s);
    if (lags.length > 50) lags.removeAt(0);
  }

  /// Numer kolejny pozycji psa – liczy luki (pakiety zgubione po drodze).
  void addSeq(int? seq) {
    if (seq == null) return;
    final last = _lastSeq;
    if (last != null && seq > last + 1 && seq - last < 1000) missingSeq += seq - last - 1;
    if (last == null || seq > last || last - seq > 1000) _lastSeq = seq;
  }

  void addLog(FixLogEntry e) {
    log.add(e);
    if (log.length > logMax) log.removeAt(0);
  }

  /// Rzeczywisty odstęp między pomiarami (mediana), null = za mało danych.
  double? get medianInterval {
    if (intervals.length < 2) return null;
    final s = [...intervals]..sort();
    return s[s.length ~/ 2];
  }

  Spread? get intervalSpread => intervals.length < 2 ? null : Spread.of(intervals);
  Spread? get lagSpread => Spread.of(lags);

  void reject(FixReject r) => rejected[r] = (rejected[r] ?? 0) + 1;

  /// Dziennik pakietów jako CSV (separator „;” – otwiera się w arkuszu).
  String csv() => [FixLogEntry.csvHeader, for (final e in log) e.toCsv()].join('\n');

  void clear() {
    packets = positions = accepted = reconnects = 0;
    bleReads = requestsSent = requestReplies = missingSeq = 0;
    _lastSeq = null;
    lastRequestAt = null;
    bleRssi = null;
    bleRssiAt = null;
    rejected.clear();
    intervals.clear();
    lags.clear();
    log.clear();
    lastError = null;
  }
}

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

  /// Identyfikator pakietu Meshtastic (MeshPacket.id), jeśli znany.
  final int? packetId;

  const CollarFix(this.node, this.lat, this.lng, this.fixAt,
      {DateTime? receivedAt,
      this.speedMs,
      this.accuracyM,
      this.sats,
      this.moved = true,
      this.timeIsFix = true,
      this.courseDeg,
      this.hdop,
      this.seq,
      this.packetId})
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

  /// Ten sam pakiet odczytany drugi raz (ten sam identyfikator pakietu).
  duplicate,

  /// Pomiar starszy niż ostatni przyjęty (pakiety w złej kolejności).
  outOfOrder,

  /// Słaby sygnał GPS: mało satelitów, fix 2D albo duży błąd pozycji.
  weak,

  /// Niemożliwy skok pozycji (prędkość ponad [FixFilter.maxSpeedMs]).
  jump,

  /// Nowy pakiet, ale ten sam pomiar GPS (ten sam czas pomiaru) – tracker
  /// wysłał pozycję, zanim GPS zmierzył nową. Nie odświeża aktualności.
  repeated,
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

  /// Ostatnie identyfikatory pakietów (do rozpoznania tego samego pakietu).
  final List<int> _packets = [];

  void reset() {
    _last = null;
    _lastMoved = null;
    _packets.clear();
  }

  /// Sprawdza pomiar. Duplikat rozpoznajemy po identyfikatorze pakietu
  /// i czasie pomiaru GPS – nigdy po samych współrzędnych: pies stojący
  /// w miejscu daje nowe pomiary z identycznymi współrzędnymi i każdy z nich
  /// odświeża aktualność pozycji. (Pole seq w Meshtastic nie numeruje
  /// pakietów – firmware zeruje je przy każdym nowym pomiarze GPS.)
  FixVerdict check(MeshPosition p, DateTime receivedAt, {int? packetId}) {
    if (packetId != null && packetId != 0) {
      if (_packets.contains(packetId)) return const FixVerdict.no(FixReject.duplicate);
      _packets.add(packetId);
      if (_packets.length > 64) _packets.removeAt(0);
    }
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
      if (timeIsFix && prev.timeIsFix) {
        if (fixAt.isBefore(prev.fixAt)) return const FixVerdict.no(FixReject.outOfOrder);
        if (fixAt == prev.fixAt) return const FixVerdict.no(FixReject.repeated);
      } else if (t != null && fixAt == prev.fixAt && same) {
        // Bez czasu pomiaru: ten sam czas i miejsce = ten sam pakiet.
        return const FixVerdict.no(FixReject.duplicate);
      } else if (t != null && fixAt.isBefore(prev.fixAt)) {
        return const FixVerdict.no(FixReject.outOfOrder);
      }
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
        seq: p.seq,
        packetId: packetId);
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
/// Surowe dane z pakietu zostają bez zmian; obok – wynik filtra i odległość.
class FixLogEntry {
  final DateTime receivedAt;
  final int node;
  final int? packetId;

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

  /// Dokładność GPS telefonu (m) w chwili pomiaru psa.
  final double? phoneAccuracyM;

  /// Wiek pozycji telefonu użytej do porównania (s, w chwili odbioru) i
  /// różnica czasu między porównywanymi pozycjami telefonu i psa (s).
  final double? phoneAgeSec, compareDtSec;

  /// Odległość pies–telefon: z surowych pomiarów i po filtrze, oraz jej
  /// szacowana niepewność (m).
  final double? distanceM, filteredDistanceM, uncertaintyM;

  /// Odpowiedź na zapytanie aplikacji o pozycję.
  final bool reply;

  /// „ok”, „postoj” albo nazwa powodu odrzucenia (duplicate = ten sam
  /// pakiet, repeated = ten sam pomiar GPS w nowym pakiecie).
  final String verdict;

  const FixLogEntry({
    required this.receivedAt,
    required this.node,
    this.packetId,
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
    this.phoneAgeSec,
    this.compareDtSec,
    this.distanceM,
    this.filteredDistanceM,
    this.uncertaintyM,
    this.reply = false,
    required this.verdict,
  });

  /// Opóźnienie: od pomiaru GPS do odbioru w telefonie (s) = wiek pozycji
  /// trackera w chwili odbioru.
  double? get lagSec => fixAt == null ? null : receivedAt.difference(fixAt!).inMilliseconds / 1000;

  static const csvHeader = 'odebrano;pomiar_gps;wyslano;wiek_pozycji_psa_s;wezel;pakiet;lat;lng;dokladnosc_m;hdop;satelity;'
      'seq;predkosc_m_s;kierunek;lora_rssi;snr;ble_rssi;dokladnosc_telefonu_m;wiek_pozycji_telefonu_s;'
      'roznica_czasu_porownania_s;odleglosc_surowa_m;odleglosc_filtr_m;niepewnosc_m;odpowiedz;wynik';

  String toCsv() {
    String n(num? v, [int digits = 1]) => v == null ? '' : (v is int ? '$v' : v.toStringAsFixed(digits));
    String d(DateTime? t) => t?.toIso8601String() ?? '';
    return [
      d(receivedAt),
      d(fixAt),
      d(sentAt),
      n(lagSec),
      meshNodeId(node),
      n(packetId),
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
      n(phoneAgeSec),
      n(compareDtSec),
      n(distanceM),
      n(filteredDistanceM),
      n(uncertaintyM),
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

  /// Przyjęte pomiary bez ruchu (postój) – odświeżają aktualność, bez dystansu.
  int still = 0;
  final Map<FixReject, int> rejected = {};
  int reconnects = 0;
  String? lastError;
  DateTime? connectedAt;
  DateTime? lastPacketAt;

  /// Odczyty Bluetooth (każdy odczyt kolejki wiadomości z urządzenia).
  int bleReads = 0;

  /// Operacje Bluetooth ponowione po błędzie i ostatni błąd GATT.
  int bleRetries = 0;
  int bleFailures = 0;
  String? lastBleError;

  /// Zapytania aplikacji o pozycję i odpowiedzi na nie.
  int requestsSent = 0;
  int requestReplies = 0;
  DateTime? lastRequestAt;

  /// Numery kolejne (seq) z pakietów psa. Meshtastic zeruje seq przy każdym
  /// nowym pomiarze GPS, więc zwykle nie numeruje pakietów – zgubione pakiety
  /// liczymy tylko, gdy numeracja wygląda wiarygodnie ([seqReliable]).
  final List<int> _seqs = [];
  int _seqGaps = 0;

  /// Sygnał Bluetooth (dBm) i kiedy go zmierzono.
  int? bleRssi;
  DateTime? bleRssiAt;

  /// Odstępy (s) między kolejnymi nowymi pomiarami psa (ostatnie 50).
  final List<double> intervals = [];

  /// Opóźnienia (s) od pomiaru GPS do odbioru (ostatnie 50, tylko gdy
  /// tracker podał czas pomiaru).
  final List<double> lags = [];

  /// Wszystkie pakiety z pozycją z tej sesji (bez obcinania aż do
  /// [logMax] ≈ 14 godzin przy pomiarze co sekundę).
  final List<FixLogEntry> log = [];
  static const logMax = 50000;

  void addInterval(double s) {
    if (s <= 0 || s > 600) return;
    intervals.add(s);
    if (intervals.length > 50) intervals.removeAt(0);
  }

  void addLag(double s) {
    if (s < 0 || s > 600) return;
    lags.add(s);
    if (lags.length > 50) lags.removeAt(0);
  }

  void addSeq(int? seq) {
    if (seq == null) return;
    if (_seqs.isNotEmpty) {
      final d = seq - _seqs.last;
      if (d > 1 && d < 1000) _seqGaps += d - 1;
    }
    _seqs.add(seq);
    if (_seqs.length > 50) _seqs.removeAt(0);
  }

  /// Numeracja wiarygodna: co najmniej 5 wartości, większość rośnie o 1.
  bool get seqReliable {
    if (_seqs.length < 5) return false;
    var up = 0;
    for (var i = 1; i < _seqs.length; i++) {
      if (_seqs[i] == _seqs[i - 1] + 1) up++;
    }
    return up >= (_seqs.length - 1) * 0.8;
  }

  /// Zgubione pakiety; null = nieznane (tracker nie numeruje pakietów).
  int? get missingSeq => seqReliable ? _seqGaps : null;

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
    packets = positions = accepted = still = reconnects = 0;
    bleReads = bleRetries = bleFailures = requestsSent = requestReplies = 0;
    _seqs.clear();
    _seqGaps = 0;
    lastRequestAt = null;
    lastBleError = null;
    bleRssi = null;
    bleRssiAt = null;
    rejected.clear();
    intervals.clear();
    lags.clear();
    log.clear();
    lastError = null;
  }
}

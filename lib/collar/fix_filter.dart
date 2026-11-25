import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../app_version.dart';
import 'app_state.dart';
import 'mesh_proto.dart';

/// Skąd przyszedł pomiar psa.
enum FixSource {
  /// Kanał Valkor BLE na żywo (każdy pomiar GNSS trackera).
  valkor,

  /// Pamięć trackera Valkor odzyskana po ponownym połączeniu.
  valkorHistory,

  /// Moduł pozycji Meshtastic (zwykłe firmware albo tryb awaryjny przy
  /// niemym kanale Valkor).
  meshtastic;

  /// Nazwa do CSV.
  String get csv => switch (this) { valkor => 'valkor', valkorHistory => 'valkor_historia', meshtastic => 'meshtastic' };
}

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

  /// Pomiar zaległy (historyczny): odebrany z dużym opóźnieniem – zwykle
  /// z kolejki trackera po (ponownym) połączeniu Bluetooth. Uzupełnia trasę,
  /// ale nie jest pozycją „na żywo” i nie uruchamia alarmów oddalenia.
  final bool historical;

  /// Pozycja wiarygodna (po stabilizacji – patrz FixTrust). Niewiarygodne
  /// pomiary nie trafiają do trasy, dystansu ani alarmów.
  final bool trusted;

  /// Czas pomiaru dokładnie tak, jak przyszedł z trackera (zegar GPS).
  final DateTime? rawFixAt;

  /// Źródło pomiaru.
  final FixSource source;

  /// Numer pomiaru GNSS w trackerze (Valkor 1.1), jeśli podany.
  final int? fixId;

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
      this.packetId,
      this.historical = false,
      this.trusted = true,
      this.rawFixAt,
      this.source = FixSource.meshtastic,
      this.fixId})
      : receivedAt = receivedAt ?? fixAt;

  LatLng get ll => LatLng(lat, lng);

  /// Ten sam pomiar z oceną wiarygodności.
  CollarFix withTrust(bool t) => CollarFix(node, lat, lng, fixAt,
      receivedAt: receivedAt,
      speedMs: speedMs,
      accuracyM: accuracyM,
      sats: sats,
      moved: moved,
      timeIsFix: timeIsFix,
      courseDeg: courseDeg,
      hdop: hdop,
      seq: seq,
      packetId: packetId,
      historical: historical,
      trusted: t,
      rawFixAt: rawFixAt,
      source: source,
      fixId: fixId);

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

  /// Pomiar z poprzedniej sesji (sprzed uruchomienia śledzenia w tej sesji
  /// albo starszy niż [FixFilter.maxHistorySec]) – np. pakiety sprzed kilku
  /// godzin z kolejki trackera. Zostaje tylko w diagnostyce.
  previousSession,

  /// Tracker oznaczył pomiar jako nieprawidłowy (brak fixu, jakość 0).
  invalid,
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
  /// Pomiar starszy niż tyle sekund w chwili odbioru jest nieaktualny
  /// (poza zaległymi pomiarami tuż po połączeniu – patrz [maxHistorySec]).
  static const maxAgeSec = 120.0;

  /// Pomiar odebrany z opóźnieniem większym niż tyle sekund jest zaległy
  /// (historyczny), gdy przychodzi tuż po połączeniu Bluetooth.
  static const backlogLagSec = 20.0;

  /// Zaległe pomiary po połączeniu przyjmujemy do trasy do tylu sekund wstecz.
  static const maxHistorySec = 900.0;

  /// Czas pomiaru „z przyszłości” większy niż tyle sekund = zły zegar
  /// trackera (np. jeszcze bez czasu z GPS) – nie ufamy czasowi z pakietu.
  /// Czas z PRZESZŁOŚCI nigdy nie jest uznawany za zły zegar: to stary
  /// pomiar (wcześniej pakiety sprzed 5 godzin dostawały czas odbioru
  /// i udawały świeże).
  static const clockSkewSec = 600.0;

  /// Tolerancja różnicy zegarów telefon–tracker (s): pomiar „z przyszłości”
  /// o tyle traktujemy jako bieżący (wiek 0).
  static const clockToleranceSec = 2.0;

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
  (LatLng, DateTime)? _jumpCand; // ostatni pomiar odrzucony jako skok

  CollarFix? get last => _last;

  /// Ostatnie identyfikatory pakietów (do rozpoznania tego samego pakietu).
  final List<int> _packets = [];

  void reset() {
    _last = null;
    _lastMoved = null;
    _jumpCand = null;
    _packets.clear();
  }

  /// Sprawdza pomiar. Duplikat rozpoznajemy po identyfikatorze pakietu
  /// i czasie pomiaru GPS – nigdy po samych współrzędnych: pies stojący
  /// w miejscu daje nowe pomiary z identycznymi współrzędnymi i każdy z nich
  /// odświeża aktualność pozycji. (Pole seq w Meshtastic nie numeruje
  /// pakietów – firmware zeruje je przy każdym nowym pomiarze GPS.)
  ///
  /// [afterConnect] = pakiet przyszedł tuż po (ponownym) połączeniu
  /// Bluetooth – wtedy opóźnione pomiary to zaległa kolejka trackera:
  /// przyjmujemy je do historii (do [maxHistorySec]) jako [CollarFix.historical].
  ///
  /// [clockOffsetSec] – szacowana różnica zegarów (telefon − tracker, s, ≤ 0
  /// gdy telefon się spóźnia): czas z trackera przeliczamy na zegar telefonu
  /// do oceny aktualności; surowy czas zostaje w [CollarFix.rawFixAt].
  /// [sessionStart] – początek śledzenia w tej sesji aplikacji: starsze
  /// pomiary to poprzednia sesja.
  FixVerdict check(MeshPosition p, DateTime receivedAt,
      {int? packetId,
      bool afterConnect = false,
      double clockOffsetSec = 0,
      DateTime? sessionStart,
      bool refUnconfirmed = false,
      FixSource source = FixSource.meshtastic}) {
    if (!p.fixValid || p.fixQuality == 0) return const FixVerdict.no(FixReject.invalid);
    if (packetId != null && packetId != 0) {
      if (_packets.contains(packetId)) return const FixVerdict.no(FixReject.duplicate);
      _packets.add(packetId);
      if (_packets.length > 64) _packets.removeAt(0);
    }
    if (p.coarse) return const FixVerdict.no(FixReject.coarse);

    // Czas pomiaru: z pakietu (przeliczony na zegar telefonu), chyba że jest
    // wyraźnie „z przyszłości” – wtedy zegar trackera jest zły.
    var fixAt = receivedAt;
    var timeIsFix = false;
    final t = p.time;
    if (t != null) {
      final local = t.add(Duration(milliseconds: (clockOffsetSec * 1000).round()));
      final skew = receivedAt.difference(local).inMilliseconds / 1000;
      // Zegar bez czasu z GPS (rok sprzed 2024) – czas z pakietu bezużyteczny.
      final unset = t.year < 2024;
      if (!unset && skew >= -clockSkewSec) {
        // Kilka sekund „z przyszłości” to różnica zegarów – wiek 0.
        fixAt = skew < 0 ? receivedAt : local;
        timeIsFix = p.timeIsFix && skew >= -clockToleranceSec;
      }
    }
    final lag = receivedAt.difference(fixAt).inMilliseconds / 1000;
    // Stary pomiar: z poprzedniej sesji albo starszy niż historia, jaką
    // przyjmujemy – tylko do diagnostyki.
    final ss = sessionStart;
    if (t != null && timeIsFix == p.timeIsFix && t.year >= 2024 && (lag > maxHistorySec || (ss != null && fixAt.isBefore(ss.subtract(const Duration(seconds: 120)))))) {
      return const FixVerdict.no(FixReject.previousSession);
    }
    if (lag > (afterConnect && timeIsFix ? maxHistorySec : maxAgeSec)) {
      return const FixVerdict.no(FixReject.stale);
    }
    final historical = timeIsFix && (lag > maxAgeSec || (afterConnect && lag > backlogLagSec));

    final prev = _last;
    // Ten sam numer pomiaru GNSS z trackera = ten sam pomiar (np. drugi pakiet).
    if (prev != null && p.fixId != null && prev.fixId == p.fixId && fixAt.isAtSameMomentAs(prev.fixAt)) {
      return const FixVerdict.no(FixReject.repeated);
    }
    if (prev != null) {
      final same = (prev.lat - p.lat).abs() < 1e-7 && (prev.lng - p.lng).abs() < 1e-7;
      // Ten sam numer kolejny i to samo miejsce = ten sam pakiet odczytany drugi raz.
      if (timeIsFix && prev.timeIsFix) {
        if (fixAt.isBefore(prev.fixAt)) return const FixVerdict.no(FixReject.outOfOrder);
        if (fixAt.isAtSameMomentAs(prev.fixAt)) return const FixVerdict.no(FixReject.repeated);
      } else if (t != null && fixAt.isAtSameMomentAs(prev.fixAt) && same) {
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
    final ll = LatLng(p.lat, p.lng);
    if (ref != null) {
      final d = _dist(ref.ll, ll);
      final dt = fixAt.difference(ref.fixAt).inMilliseconds / 1000;
      final impossible = (dt > 0 && d / dt > maxSpeedMs) || (dt <= 0 && d > 20);
      // Skok odrzucamy tylko względem pozycji już ustalonej. W czasie
      // stabilizacji ([refUnconfirmed]) błędny bywa właśnie punkt odniesienia
      // (np. pierwszy pomiar 113 m obok) – wtedy decyduje ocena serii
      // (FixTrust), a nie odrzucanie poprawnych pomiarów przez kolejne sekundy.
      if (impossible && !refUnconfirmed) {
        // Dwa kolejne pomiary zgodne ze sobą, a daleko od odniesienia:
        // to odniesienie było błędne – przyjmujemy nowe miejsce.
        final c = _jumpCand;
        final cdt = c == null ? 0.0 : fixAt.difference(c.$2).inMilliseconds / 1000;
        final cd = c == null ? 0.0 : _dist(c.$1, ll);
        final consistent = c != null && ((cdt > 0 && cd / cdt <= maxSpeedMs) || (cdt <= 0 && cd <= 20));
        if (!consistent) {
          _jumpCand = (ll, fixAt);
          return const FixVerdict.no(FixReject.jump);
        }
      }
      moved = impossible || !isDrift(d, p.accuracyM, p.speedMs);
    }
    _jumpCand = null;

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
        packetId: packetId,
        historical: historical,
        rawFixAt: t,
        source: source,
        fixId: p.fixId);
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

  /// Pomiar zaległy (z kolejki po ponownym połączeniu).
  final bool historical;

  /// Dlaczego odległość nie została policzona (null = policzona).
  final String? noDistanceReason;

  /// Pozycja wiarygodna po stabilizacji (null = nie oceniano).
  final bool? trusted;

  /// Szacowana różnica zegarów telefon − tracker w chwili odbioru (s).
  final double? clockOffsetSec;

  /// „ok”, „postoj” albo nazwa powodu odrzucenia (duplicate = ten sam
  /// pakiet, repeated = ten sam pomiar GPS w nowym pakiecie).
  final String verdict;

  /// Źródło pomiaru: valkor, valkor_historia, meshtastic.
  final String? source;

  /// Numer kolejny pakietu Valkor i numer pomiaru GNSS (fixId).
  final int? valkorSeq, fixId;

  /// Czas pomiaru GNSS w UTC dokładnie jak w pakiecie (null = tracker nie podał).
  final DateTime? gnssUtc;

  /// Skąd czas pomiaru: „gnss” (z odbiornika) albo „odbior” (nieznany –
  /// przyjęto chwilę odbioru, wyraźnie oznaczone).
  final String? timeSource;

  /// Wiek pozycji w chwili odbioru po korekcie zegara telefon–tracker (s).
  final double? correctedAgeSec;

  /// Opóźnienie GNSS → wysłanie przez Bluetooth zmierzone w trackerze (ms).
  final int? gnssToBleMs;

  /// Odstęp od poprzedniej pozycji Valkor na żywo (s) – przerwa w transmisji.
  final double? rxGapSec;

  /// MTU połączenia, RSSI trackera (z Diag), bateria, jakość fixu, flaga postoju.
  final int? mtu, trackerRssi, batteryPct, batteryMv, fixQuality;
  final bool? stationaryFlag;

  /// Stan aplikacji w chwili odbioru: pierwszy_plan / tlo.
  final String? appState;

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
    this.historical = false,
    this.noDistanceReason,
    this.trusted,
    this.clockOffsetSec,
    this.source,
    this.valkorSeq,
    this.fixId,
    this.gnssUtc,
    this.timeSource,
    this.correctedAgeSec,
    this.gnssToBleMs,
    this.rxGapSec,
    this.mtu,
    this.trackerRssi,
    this.batteryPct,
    this.batteryMv,
    this.fixQuality,
    this.stationaryFlag,
    this.appState,
  });

  /// Opóźnienie: od pomiaru GPS do odbioru w telefonie (s) = wiek pozycji
  /// trackera w chwili odbioru.
  double? get lagSec => fixAt == null ? null : receivedAt.difference(fixAt!).inMilliseconds / 1000;

  static const csvHeader = 'odebrano;pomiar_gps;wyslano;wiek_pozycji_psa_s;wezel;pakiet;lat;lng;dokladnosc_m;hdop;satelity;'
      'seq;predkosc_m_s;kierunek;lora_rssi;snr;ble_rssi;dokladnosc_telefonu_m;wiek_pozycji_telefonu_s;'
      'roznica_czasu_porownania_s;odleglosc_surowa_m;odleglosc_filtr_m;niepewnosc_m;odpowiedz;wynik;historyczny;'
      'brak_odleglosci;wiarygodna;roznica_zegarow_s;zrodlo;valkor_seq;fix_id;gnss_utc;odebrano_utc;czas_pomiaru_zrodlo;'
      'wiek_skorygowany_s;opoznienie_gnss_ble_ms;przerwa_odbioru_s;mtu;rssi_tracker;bateria_proc;bateria_mv;jakosc_fix;'
      'postoj_tracker;stan_aplikacji';

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
      historical ? '1' : '0',
      (noDistanceReason ?? '').replaceAll(';', ','),
      trusted == null ? '' : (trusted! ? '1' : '0'),
      n(clockOffsetSec),
      source ?? '',
      n(valkorSeq),
      n(fixId),
      gnssUtc?.toUtc().toIso8601String() ?? '',
      receivedAt.toUtc().toIso8601String(),
      timeSource ?? '',
      n(correctedAgeSec, 2),
      n(gnssToBleMs),
      n(rxGapSec, 2),
      n(mtu),
      n(trackerRssi),
      n(batteryPct),
      n(batteryMv),
      n(fixQuality),
      stationaryFlag == null ? '' : (stationaryFlag! ? '1' : '0'),
      appState ?? '',
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

  /// Błędy Bluetooth wg kodu (np. deviceDisconnected, readFailed) i ile
  /// z nich wystąpiło, gdy połączenie było już zerwane (skutek utraty, nie
  /// osobny problem).
  final Map<String, int> bleErrorCodes = {};
  int bleErrorsWhileDown = 0;
  DateTime? lastBleErrorAt;

  /// Zdarzenia połączenia Bluetooth (utrata, ponowne połączenie, błąd).
  final List<BleEvent> bleEvents = [];

  /// Pomiary zaległe (z kolejki trackera po ponownym połączeniu).
  int historical = 0;

  /// MTU: rzeczywista wynegocjowana wartość (null = nieznana), kiedy,
  /// liczba prób i ostatni błąd negocjacji.
  int? mtu;
  DateTime? mtuAt;
  int mtuAttempts = 0;
  String? mtuError;

  /// MTU wystarcza na pakiety Valkor (null = nieznane).
  bool? get mtuOk => mtu == null ? null : mtu! >= 67;

  /// Pomiary z poprzedniej sesji (np. sprzed kilku godzin) – tylko w dzienniku.
  int previousSession = 0;

  /// Różnica „odbiór − wysłanie” (s) z ostatnich pakietów: czas wysłania
  /// pochodzi z zegara GPS trackera (pełne sekundy), odbiór – z zegara
  /// telefonu. Ujemna = zegar telefonu spóźnia się względem GPS.
  final List<double> clockSamples = [];

  void addClock(DateTime rx, DateTime? sent) {
    if (sent == null) return;
    final d = rx.difference(sent).inMilliseconds / 1000;
    // Pakiet sprzed wielu minut nic nie mówi o zegarze (zaległy).
    if (d.abs() > 60) return;
    clockSamples.add(d);
    if (clockSamples.length > 30) clockSamples.removeAt(0);
  }

  /// Szacowana różnica zegarów telefon − tracker (s): ≤ 0. Najmniejsza
  /// różnica „odbiór − wysłanie” to opóźnienie przesyłu + różnica zegarów;
  /// gdy jest ujemna, zegar telefonu na pewno spóźnia się co najmniej tyle.
  /// Dodatniej różnicy nie da się oddzielić od opóźnienia – wtedy 0.
  double get clockOffsetSec {
    if (clockSamples.isEmpty) return 0;
    final m = clockSamples.reduce(math.min);
    return m < 0 ? m : 0;
  }

  /// Odstępy (s) między kolejnymi pakietami z pozycją psa wg chwili odbioru
  /// w telefonie – niezależnie od czasu pomiaru GPS (ostatnie 100).
  final List<double> rxIntervals = [];
  DateTime? _lastRxAt;

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
    if (s < -5 || s > 600) return;
    lags.add(s);
    if (lags.length > 50) lags.removeAt(0);
  }

  void addRx(DateTime t) {
    final p = _lastRxAt;
    _lastRxAt = t;
    if (p == null) return;
    final s = t.difference(p).inMilliseconds / 1000;
    if (s <= 0 || s > 3600) return;
    rxIntervals.add(s);
    if (rxIntervals.length > 100) rxIntervals.removeAt(0);
  }

  Spread? get rxSpread => rxIntervals.length < 2 ? null : Spread.of(rxIntervals);

  void addBleEvent(DateTime t, String kind, [String? detail]) {
    bleEvents.add(BleEvent(t, kind, detail));
    if (bleEvents.length > 500) bleEvents.removeAt(0);
  }

  /// Ostatnia utrata połączenia i ile trwała przerwa (s) do ponownego połączenia.
  BleEvent? get lastLoss {
    for (final e in bleEvents.reversed) {
      if (e.kind == BleEvent.lost) return e;
    }
    return null;
  }

  /// Ostatnie ponowne połączenie po utracie.
  BleEvent? get lastReconnect {
    for (final e in bleEvents.reversed) {
      if (e.kind == BleEvent.connected) return e;
    }
    return null;
  }

  void noteBleError(Object e, {required bool down, required DateTime at}) {
    lastBleError = bleErrorText(e);
    lastBleErrorAt = at;
    final code = bleErrorCode(e);
    bleErrorCodes[code] = (bleErrorCodes[code] ?? 0) + 1;
    if (down) bleErrorsWhileDown++;
  }

  /// Krótki kod błędu Bluetooth (nazwa kodu UniversalBle albo numer GATT).
  static String bleErrorCode(Object e) {
    final s = e.toString();
    final m = RegExp(r'Code: (?:UniversalBleErrorCode\.)?(\w+)').firstMatch(s);
    if (m != null) return m.group(1)!;
    final g = RegExp(r'\b(133|8|19|22|62|257)\b').firstMatch(s);
    if (g != null) return 'gatt_${g.group(1)}';
    return e.runtimeType.toString();
  }

  /// Czytelny, przycięty opis błędu Bluetooth.
  static String bleErrorText(Object e) {
    var s = e.toString().replaceFirst('UniversalBleException: ', '').replaceAll('UniversalBleErrorCode.', '');
    s = s.replaceAll(RegExp(r',? Details: null'), '');
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
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
  /// Pod tabelą pakietów – osobne sekcje: zdarzenia Bluetooth i [extra]
  /// (np. podsumowanie GPS telefonu).
  String csv({List<String> extra = const []}) {
    String n(double? v) => v == null ? '' : v.toStringAsFixed(1);
    final rx = rxSpread;
    return [
      FixLogEntry.csvHeader,
      for (final e in log) e.toCsv(),
      '',
      'zdarzenie_bluetooth;czas;szczegoly',
      for (final e in bleEvents) '${e.kind};${e.at.toIso8601String()};${(e.detail ?? '').replaceAll(';', ',').replaceAll('\n', ' ')}',
      '',
      'podsumowanie;nazwa;wartosc',
      'aplikacja;wersja;$appVersion',
      'aplikacja;kompilacja;$appBuildId',
      'bluetooth;mtu;${mtu ?? ''}',
      'bluetooth;mtu_wymagane_valkor;67',
      'bluetooth;mtu_negocjacja_udana;${mtuOk == null ? '' : (mtuOk! ? 1 : 0)}',
      'bluetooth;mtu_proby;$mtuAttempts',
      if (mtuError != null) 'bluetooth;mtu_blad;${mtuError!.replaceAll(';', ',')}',
      'bluetooth;pakiety_historyczne;$historical',
      'bluetooth;pakiety_poprzedniej_sesji;$previousSession',
      'zegar;roznica_telefon_tracker_s;${clockOffsetSec.toStringAsFixed(2)}',
      'bluetooth;odstep_odbioru_min_sr_max_s;${n(rx?.min)};${n(rx?.avg)};${n(rx?.max)}',
      'bluetooth;ponowne_polaczenia;$reconnects',
      'bluetooth;bledy_wg_kodu;${bleErrorCodes.entries.map((e) => '${e.key}=${e.value}').join(',')}',
      'bluetooth;bledy_po_utracie_polaczenia;$bleErrorsWhileDown',
      ...extra,
    ].join('\n');
  }

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
    rxIntervals.clear();
    _lastRxAt = null;
    bleEvents.clear();
    bleErrorCodes.clear();
    bleErrorsWhileDown = 0;
    lastBleErrorAt = null;
    historical = 0;
    previousSession = 0;
    mtu = null;
    mtuAt = null;
    mtuAttempts = 0;
    mtuError = null;
    clockSamples.clear();
    lags.clear();
    log.clear();
    lastError = null;
  }
}

/// Zdarzenie połączenia Bluetooth (do diagnostyki i CSV).
class BleEvent {
  static const lost = 'utrata';
  static const connected = 'polaczono';
  static const failed = 'blad_polaczenia';
  static const valkorReinit = 'valkor_ponowienie';

  final DateTime at;
  final String kind;
  final String? detail;
  const BleEvent(this.at, this.kind, [this.detail]);
}

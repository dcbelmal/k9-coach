// Stan połączenia z trackerem z firmware Valkor Track (bezpośredni kanał GPS
// przez Bluetooth). Tworzony, gdy po połączeniu urządzenie ma usługę Valkor;
// bez niej aplikacja działa jak dotąd, tylko przez protokół Meshtastic.
import '../l10n/l10n.dart';
import 'mesh_proto.dart';
import 'valkor_proto.dart';

/// Stan kanału Valkor w bieżącym połączeniu Bluetooth.
enum ValkorChannel {
  /// Usługa Valkor wykryta, subskrypcja jeszcze nie działa (albo błąd).
  detected,

  /// Powiadomienia włączone, czekamy na pierwszy pakiet.
  subscribed,

  /// Protokół Valkor potwierdzony (poprawny pakiet), brak pozycji.
  confirmed,

  /// Odbiór aktualnych pozycji.
  receiving,

  /// Kanał był albo powinien być aktywny, ale pakiety nie przychodzą.
  silent,
}

/// Pobieranie historii z pamięci trackera.
enum HistorySync { idle, requested, receiving, done }

class ValkorSession {
  /// Usługa Valkor znaleziona w urządzeniu.
  final DateTime detectedAt;
  ValkorSession(this.detectedAt);

  ValkorInfo? info;
  ValkorStatus? status;
  DateTime? statusAt;
  ValkorDiag? diag;
  ValkorPerf? perf;
  ValkorBuildInfo? buildInfo;
  ValkorAck? lastAck;
  final stats = ValkorLinkStats();

  /// Wersja firmware Valkor i tryb z ostatniego pakietu.
  String? firmware;
  ValkorMode? deviceMode;
  bool insecure = false;
  DateTime? lastRx;
  int? lastSeq;

  /// Ostatnia pozycja na żywo z kanału Valkor (surowy pakiet) i chwila odbioru.
  ValkorPosition? lastPosition;
  DateTime? lastPositionAt;
  int? batteryMv;

  /// Rzeczywiste MTU połączenia (null = nieznane, np. iOS).
  int? mtu;

  // --- bieżące połączenie Bluetooth ---
  DateTime? detectedThisConnectionAt;
  DateTime? subscribedAt;
  String? subscribeError;
  int subscribeErrors = 0;
  DateTime? lastRxThisConnection;
  int reinitThisConnection = 0;
  DateTime? lastReinitAt;
  String? lastReinitReason;

  /// Ponowienia inicjalizacji kanału (cała sesja).
  int reinits = 0;
  int connections = 0;

  /// Pozycje Meshtastic tego samego trackera pominięte, bo przychodzą kanałem Valkor.
  int meshIgnored = 0;

  /// Pozycje Meshtastic tego trackera przyjęte w trybie awaryjnym (kanał Valkor niemy).
  int meshFallback = 0;

  /// Historia z pamięci trackera: przyjęte, odrzucone (zły fix, słaby sygnał,
  /// poprzednia sesja), duplikaty i ile z przyjętych było starszych niż
  /// bieżąca pozycja na żywo (wstawione w środek trasy).
  int historyRecovered = 0, historyRejected = 0, historyDuplicates = 0, historyBeforeLive = 0;
  final Set<int> historySeen = {};
  DateTime? historySyncRequestedAt;

  /// Czasy pomiarów odebranych na żywo (ostatnie [_liveSeenMax]) – historia
  /// z tym samym czasem to duplikat (firmware 0.1.2 ponawia pozycje wysłane
  /// tuż przed zerwaniem połączenia).
  final Set<int> liveSeen = {};
  final List<int> _liveOrder = [];
  static const _liveSeenMax = 1200;

  /// Przyczyny odrzucenia pozycji historycznych (nazwa → liczba).
  final Map<String, int> historyRejectReasons = {};

  /// Pobieranie historii: stan, ile tracker zapowiedział (Ack, 255 = 255 lub
  /// więcej), ile przyszło w tym pobraniu, ostatni pakiet, koniec.
  HistorySync historySync = HistorySync.idle;
  int? historyExpected;
  int historyReceivedThisSync = 0;
  DateTime? historyLastAt, historyDoneAt;
  int historySyncs = 0;

  void noteLive(DateTime? fixTime) {
    if (fixTime == null) return;
    final ms = fixTime.millisecondsSinceEpoch;
    if (liveSeen.add(ms)) {
      _liveOrder.add(ms);
      if (_liveOrder.length > _liveSeenMax) liveSeen.remove(_liveOrder.removeAt(0));
    }
  }

  void noteHistoryReject(String why) => historyRejectReasons[why] = (historyRejectReasons[why] ?? 0) + 1;

  void onHistoryRequested(DateTime t) {
    historySyncRequestedAt = t;
    historySync = HistorySync.requested;
    historyExpected = null;
    historyReceivedThisSync = 0;
    historyLastAt = null;
    historySyncs++;
  }

  void onHistoryAck(int count, DateTime t) {
    historyExpected = count;
    if (count == 0) {
      historySync = HistorySync.done;
      historyDoneAt = t;
    } else if (historySync != HistorySync.receiving) {
      historySync = HistorySync.receiving;
    }
  }

  void onHistoryPacket(DateTime t) {
    historyReceivedThisSync++;
    historyLastAt = t;
    historySync = HistorySync.receiving;
  }

  /// Koniec pobierania: wszystko, co tracker zapowiedział, albo 3 s ciszy.
  bool historyDoneDue(DateTime t) {
    if (historySync != HistorySync.receiving && historySync != HistorySync.requested) return false;
    final exp = historyExpected;
    if (exp != null && exp < 255 && historyReceivedThisSync >= exp && historyReceivedThisSync > 0) return true;
    final last = historyLastAt ?? historySyncRequestedAt;
    return last != null && t.difference(last).inMilliseconds >= 3000 && (historyLastAt != null || exp != null);
  }

  void onHistoryDone(DateTime t) {
    historySync = HistorySync.done;
    historyDoneAt = t;
  }

  /// Czy pobrano tyle, ile tracker zapowiedział (null = nie wiadomo).
  bool? get historyComplete {
    final e = historyExpected;
    if (e == null || e >= 255 || historySync != HistorySync.done) return null;
    return historyReceivedThisSync >= e;
  }

  /// Liczniki firmware (narastające od uruchomienia trackera) z początku
  /// sesji testowej – do liczników „w tej sesji”.
  ValkorDiag? diagBaseline;

  /// Urządzenie odpowiada protokołem Valkor (przyszedł poprawny pakiet).
  bool get confirmed => lastRx != null;

  /// Odstęp wysyłki w trybie ustawionym w trackerze (s).
  int? get periodSec => deviceMode?.periodSec;

  /// Wersja protokołu (z BuildInfo; firmware 0.1.0 nie wysyła BuildInfo – „1.0”).
  String get protocol => buildInfo?.protocol ?? (confirmed ? '1.0' : '');

  /// Rzeczywisty odstęp pomiarów GNSS zmierzony przez tracker (s).
  double? get gnssIntervalSec {
    final p = perf;
    if (p != null && p.gnssIntMedianMs > 0) return p.gnssIntMedianMs / 1000;
    final d = diag;
    return d == null || d.gnssIntervalAvgMs == 0 ? null : d.gnssIntervalAvgMs / 1000;
  }

  /// Protokół 1.2 (firmware 0.1.2+): surowe dane odbiornika dla ostatnich
  /// pozycji (wg fixId), liczniki NMEA i czy aplikacja poprosiła o szczegóły
  /// w tym połączeniu. Firmware 0.1.1 tego nie ma – wtedy wszystko null.
  final Map<int, ValkorFixDetail> details = {};
  ValkorFixDetail? lastDetail;
  ValkorGnssStats? gnssStats;

  /// Bufor historii i wysyłka BLE w trackerze (firmware 0.1.2 po 27.11).
  ValkorTrackerLink? trackerLink;
  bool detailRequested = false;
  int detailPackets = 0;

  /// Tracker obsługuje pakiety FixDetail / GnssStats.
  bool get supportsDetail => ((info?.capabilities ?? 0) & ValkorCap.fixDetail) != 0;

  bool get supportsTrackerLink => ((info?.capabilities ?? 0) & ValkorCap.linkStats) != 0;

  /// RSSI zmierzone przez tracker w tym połączeniu (min / suma / liczba).
  int? trackerRssiMin;
  int _trackerRssiSum = 0, _trackerRssiN = 0;
  int? get trackerRssiAvg => _trackerRssiN == 0 ? null : (_trackerRssiSum / _trackerRssiN).round();

  void onTrackerLink(ValkorTrackerLink l) {
    trackerLink = l;
    final r = l.rssiNow;
    if (r != null) {
      _trackerRssiSum += r;
      _trackerRssiN++;
      if (trackerRssiMin == null || r < trackerRssiMin!) trackerRssiMin = r;
    }
  }

  void addDetail(ValkorFixDetail d) {
    detailPackets++;
    lastDetail = d;
    details[d.fixId] = d;
    while (details.length > 16) {
      details.remove(details.keys.first);
    }
  }

  /// Szczegóły dla pomiaru [fixId]; gdy jeszcze nie dotarły (FixDetail
  /// przychodzi tuż po pozycji) – ostatnie znane (błąd GST zmienia się powoli).
  ValkorFixDetail? detailFor(int? fixId) => (fixId == null ? null : details[fixId]) ?? lastDetail;

  void onDetected(DateTime t, {int? mtu}) {
    detectedThisConnectionAt = t;
    detailRequested = false;
    subscribedAt = null;
    subscribeError = null;
    lastRxThisConnection = null;
    reinitThisConnection = 0;
    lastReinitAt = null;
    connections++;
    if (mtu != null) this.mtu = mtu;
  }

  void onSubscribed(DateTime t) {
    subscribedAt = t;
    subscribeError = null;
  }

  void onSubscribeError(DateTime t, String e) {
    subscribeError = e;
    subscribeErrors++;
  }

  void onReinit(DateTime t, String why) {
    reinitThisConnection++;
    reinits++;
    lastReinitAt = t;
    lastReinitReason = why;
  }

  void onPacket(DateTime t) {
    lastRx = t;
    lastRxThisConnection = t;
  }

  void onDisconnected() {
    subscribedAt = null;
    trackerRssiMin = null;
    _trackerRssiSum = _trackerRssiN = 0;
    detectedThisConnectionAt = null;
    // Pobieranie przerwane rozłączeniem – po ponownym połączeniu od nowa.
    if (historySync == HistorySync.requested || historySync == HistorySync.receiving) historySync = HistorySync.idle;
  }

  void onDiag(ValkorDiag d) {
    // Mniejszy czas pracy = tracker uruchomił się ponownie: nowa podstawa.
    final b = diagBaseline;
    if (b == null || d.uptimeS < b.uptimeS) diagBaseline = d;
    diag = d;
  }

  /// Nowa sesja testowa: liczniki telefonu od zera, liczniki firmware od bieżącej wartości.
  void resetSession() {
    stats.resetSession();
    diagBaseline = diag;
    meshIgnored = meshFallback = 0;
    historyRecovered = historyRejected = historyDuplicates = historyBeforeLive = 0;
    historyRejectReasons.clear();
    historySyncs = 0;
    reinits = 0;
  }

  /// Stan kanału w chwili [t] ([delivering] – patrz CollarLink.valkorDelivering).
  ValkorChannel channel(DateTime t, {required bool delivering}) {
    if (subscribedAt == null && lastRxThisConnection == null) return ValkorChannel.detected;
    if (!delivering) {
      final rx = lastRxThisConnection;
      final since = rx ?? subscribedAt!;
      // Krótko po subskrypcji – jeszcze czekamy na pierwszy pakiet.
      if (rx == null && t.difference(since).inSeconds < 6) return ValkorChannel.subscribed;
      return ValkorChannel.silent;
    }
    final p = lastPositionAt;
    if (p != null && t.difference(p).inSeconds <= 5 * (periodSec ?? 1) + 2) return ValkorChannel.receiving;
    return ValkorChannel.confirmed;
  }

  /// Licznik firmware w bieżącej sesji testowej (różnica od podstawy).
  int sessionDelta(int Function(ValkorDiag d) f) {
    final d = diag, b = diagBaseline;
    if (d == null) return 0;
    if (b == null || identical(b, d)) return b == null ? f(d) : 0;
    final v = f(d) - f(b);
    return v < 0 ? f(d) : v;
  }

  List<String> csvLines() {
    final i = info, d = diag, s = status, b = buildInfo, p = perf;
    String n(double? v) => v == null ? '' : v.toStringAsFixed(2);
    return [
      '',
      'valkor;nazwa;wartosc',
      'valkor;firmware;${firmware ?? ''}',
      'valkor;firmware_nazwa;${b?.name ?? ''}',
      'valkor;firmware_kompilacja;${b?.buildId ?? ''}',
      'valkor;firmware_commit;${b?.commit ?? ''}',
      'valkor;protokol;$protocol',
      'valkor;baza_meshtastic;${i?.upstream ?? ''}',
      'valkor;urzadzenie;${i?.hwName ?? ''}',
      'valkor;tryb;${deviceMode?.name ?? ''}',
      'valkor;mtu;${mtu ?? ''}',
      'valkor;mtu_wymagane;${ValkorBle.minMtu}',
      'valkor;polaczenie_bez_szyfrowania;$insecure',
      'valkor;ponowienia_inicjalizacji;$reinits',
      'valkor;bledy_subskrypcji;$subscribeErrors',
      // Liczniki telefonu – od początku sesji testowej.
      'valkor_sesja;pakiety;${stats.packets}',
      'valkor_sesja;pozycje_na_zywo;${stats.live}',
      'valkor_sesja;pozycje_historyczne_odebrane;${stats.historical}',
      'valkor_sesja;historia_przyjeta;$historyRecovered',
      'valkor_sesja;historia_odrzucona;$historyRejected',
      'valkor_sesja;historia_duplikaty;$historyDuplicates',
      'valkor_sesja;historia_wstawiona_przed_pozycja_na_zywo;$historyBeforeLive',
      'valkor_sesja;historia_pobrania;$historySyncs',
      'valkor_sesja;historia_stan;${historySync.name}',
      'valkor_sesja;historia_zapowiedziana_ostatnio;${historyExpected ?? ''}',
      'valkor_sesja;historia_odebrana_ostatnio;$historyReceivedThisSync',
      'valkor_sesja;historia_kompletna;${historyComplete == null ? 'nieznane' : (historyComplete! ? 1 : 0)}',
      'valkor_sesja;historia_odrzucona_wg_przyczyny;${historyRejectReasons.entries.map((e) => '${e.key}=${e.value}').join(',')}',
      'valkor_sesja;statusy;${stats.status}',
      'valkor_sesja;utracone_pakiety;${stats.lost}',
      'valkor_sesja;powtorzone_pakiety;${stats.duplicates}',
      'valkor_sesja;bledne_ramki;${stats.badFrames}',
      'valkor_sesja;restarty_trackera;${stats.restarts}',
      'valkor_sesja;mediana_odstepu_odbioru_s;${n(stats.medianLiveInterval)}',
      'valkor_sesja;najdluzsza_przerwa_odbioru_s;${n(stats.maxLiveGapSec)}',
      'valkor_sesja;przerwy_ponad_2s;${stats.liveGapsOver2s}',
      'valkor_sesja;pozycje_meshtastic_pominiete;$meshIgnored',
      'valkor_sesja;pozycje_meshtastic_tryb_awaryjny;$meshFallback',
      if (d != null) ...[
        'valkor_sesja;gnss_pomiary_wszystkie;${sessionDelta((x) => x.fixesTotal)}',
        'valkor_sesja;gnss_pomiary_odrzucone;${sessionDelta((x) => x.fixesRejected)}',
        'valkor_sesja;wyslane_na_zywo;${sessionDelta((x) => x.liveSent)}',
        'valkor_sesja;wyslane_historia;${sessionDelta((x) => x.historySent)}',
        'valkor_sesja;bledy_wysylki_ble;${sessionDelta((x) => x.notifyFailed)}',
        // Liczniki firmware – narastające od uruchomienia trackera.
        'valkor_fw_od_startu;czas_pracy_s;${d.uptimeS}',
        'valkor_fw_od_startu;gnss_pomiary_wszystkie;${d.fixesTotal}',
        'valkor_fw_od_startu;gnss_pomiary_odrzucone;${d.fixesRejected}',
        'valkor_fw_od_startu;gnss_odstep_sr_ms;${d.gnssIntervalAvgMs}',
        'valkor_fw_od_startu;gnss_odstep_max_ms;${d.gnssIntervalMaxMs}',
        'valkor_fw_od_startu;wyslane_na_zywo;${d.liveSent}',
        'valkor_fw_od_startu;wyslane_historia;${d.historySent}',
        'valkor_fw_od_startu;bledy_wysylki_ble;${d.notifyFailed}',
        'valkor_fw_od_startu;za_male_mtu;${d.mtuTooSmall}',
        'valkor_fw_od_startu;polaczenia_ponowne;${d.reconnects}',
        'valkor_fw_od_startu;historia_w_pamieci;${d.historyStored}',
        'valkor_fw_od_startu;historia_utracona;${d.historyDropped}',
        'valkor_fw_od_startu;rssi_tracker_dbm;${d.rssi == 0 ? 'niedostepne' : d.rssi}',
        'valkor_fw_od_startu;wolna_pamiec_kb;${d.freeHeapKb}',
        'valkor_fw_od_startu;opoznienie_sr_ms;${d.latencyAvgMs}',
        'valkor_fw_od_startu;opoznienie_max_ms;${d.latencyMaxMs}',
      ],
      if (p != null) ...[
        'valkor_fw_okno_10s;gnss_odstep_mediana_ms;${p.gnssIntMedianMs}',
        'valkor_fw_okno_10s;ble_odstep_mediana_ms;${p.bleIntMedianMs}',
        'valkor_fw_okno_10s;ble_odstep_max_ms;${p.bleIntMaxMs}',
        'valkor_fw_okno_10s;opoznienie_gnss_ble_mediana_ms;${p.latencyMedianMs}',
        'valkor_fw_okno_10s;nowe_pomiary;${p.windowFixes}',
        'valkor_fw_od_startu;nmea_poprawne;${p.nmeaOk}',
        'valkor_fw_od_startu;nmea_bledne;${p.nmeaBad}',
        'valkor_fw_od_startu;pomiary_pominiete;${p.fixesSkipped}',
        'valkor_fw_od_startu;pomiary_ta_sama_pozycja;${p.samePosition}',
        'valkor_fw_od_startu;kolejka_pelna;${p.queueFull}',
        'valkor_fw_od_startu;temperatura_c;${p.tempC ?? ''}',
      ],
      ...trackerLinkCsv(),
      if (s != null) 'valkor;bateria_proc;${s.batteryPct ?? ''}',
      'valkor;bateria_mv;${batteryMv ?? s?.batteryMv ?? ''}',
    ];
  }

  /// Bufor historii i wysyłka w trackerze (pakiet LinkStats). Firmware bez
  /// tego pakietu: jeden wiersz „niedostepne”.
  List<String> trackerLinkCsv() {
    final l = trackerLink;
    String dbm(int? v) => v == null ? 'niedostepne' : '$v';
    if (l == null) return ['valkor_fw_lacze;pakiet_linkstats;niedostepne'];
    return [
      'valkor_fw_lacze;historia_do_wyslania;${l.historyUnsent}',
      'valkor_fw_lacze;historia_w_drodze;${l.historyInflight}',
      'valkor_fw_lacze;historia_pojemnosc;${l.historyCapacity}',
      'valkor_fw_lacze;historia_trwa_wysylka;${l.syncActive ? 1 : 0}',
      'valkor_fw_od_startu;historia_przywrocona_po_rozlaczeniu;${l.historyRestored}',
      'valkor_fw_od_startu;na_zywo_nieprzyjete_zapisane_w_historii;${l.liveFailedStored}',
      'valkor_fw_od_startu;historia_w_drodze_nadpisana;${l.historyLostInflight}',
      'valkor_fw_od_startu;niewyslane_za_male_mtu;${l.mtuTooSmall}',
      'valkor_fw_od_startu;niewyslane_kolejka_pelna;${l.queueFull}',
      'valkor_fw_od_startu;niewyslane_blad_lacza;${l.notifyErrors}',
      'valkor_fw_od_startu;polaczenia;${l.connects}',
      'valkor_fw_lacze;czas_polaczenia_s;${l.connectedS}',
      'valkor_fw_lacze;rssi_tracker_teraz_dbm;${dbm(l.rssiNow)}',
      'valkor_fw_lacze;rssi_tracker_min_dbm;${dbm(l.rssiMin)}',
      'valkor_fw_lacze;rssi_tracker_sr_dbm;${dbm(l.rssiAvg)}',
    ];
  }

  /// Wiersze do ekranu diagnostyki (etykieta, wartość).
  List<(String, String)> rows() {
    final i = info, d = diag, b = buildInfo, p = perf;
    String s1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final m = stats.medianLiveInterval;
    return [
      (tr('Firmware'), firmware == null ? '–' : 'Valkor Track $firmware${i == null ? '' : ' (Meshtastic ${i.upstream})'}'),
      if (b != null) (tr('Kompilacja firmware'), '${b.buildId} · ${b.commit} · ${tr('protokół')} ${b.protocol}'),
      if (i != null) (tr('Urządzenie'), i.hwName),
      (tr('Tryb w trackerze'), deviceMode == null ? '–' : deviceMode!.name.toUpperCase()),
      (tr('MTU (rzeczywiste / wymagane)'), '${mtu ?? '?'} / ${ValkorBle.minMtu}'),
      if (insecure) (tr('Uwaga'), tr('połączenie bez szyfrowania – ustaw PIN Bluetooth w trackerze')),
      (tr('Odstęp pomiarów GNSS (zmierzony w trackerze)'), gnssIntervalSec == null ? '–' : tr('~{0} s', [s1(gnssIntervalSec!)])),
      if (d != null) (tr('Najdłuższy odstęp GNSS (od startu trackera)'), tr('{0} s', [s1(d.gnssIntervalMaxMs / 1000)])),
      (tr('Odstęp odbioru pozycji w telefonie'), m == null ? '–' : tr('~{0} s', [s1(m)])),
      (tr('Najdłuższa przerwa odbioru'), tr('{0} s', [s1(stats.maxLiveGapSec)])),
      if (p != null) (tr('Opóźnienie GNSS → Bluetooth (mediana)'), '${p.latencyMedianMs} ms'),
      if (d != null) (tr('Opóźnienie w trackerze śr. / max'), '${d.latencyAvgMs} / ${d.latencyMaxMs} ms'),
      (tr('Pakiety Valkor / utracone / powtórzone'), '${stats.packets} / ${stats.lost} / ${stats.duplicates}'),
      (tr('Pozycje na żywo / historyczne'), '${stats.live} / ${stats.historical}'),
      if (historyRecovered + historyRejected + historyDuplicates > 0)
        (tr('Historia: przyjęta / odrzucona / duplikaty'), '$historyRecovered / $historyRejected / $historyDuplicates'),
      if (meshFallback > 0) (tr('Pozycje Meshtastic w trybie awaryjnym'), '$meshFallback'),
      if (reinits > 0) (tr('Ponowienia kanału Valkor'), '$reinits${lastReinitReason == null ? '' : ' ($lastReinitReason)'}'),
      if (subscribeError != null) (tr('Błąd subskrypcji'), subscribeError!),
      if (stats.badFrames > 0) (tr('Błędne ramki'), '${stats.badFrames}'),
      if (stats.restarts > 0) (tr('Restarty trackera'), '${stats.restarts}'),
      if (d != null) (tr('GNSS: pomiary / odrzucone (od startu trackera)'), '${d.fixesTotal} / ${d.fixesRejected}'),
      if (d != null) (tr('Sygnał Bluetooth w trackerze'), d.rssi == 0 ? '–' : '${d.rssi} dBm'),
      if (d != null) (tr('Czas pracy trackera'), tr('{0} min', [(d.uptimeS / 60).floor()])),
      if (d != null) (tr('Wolna pamięć trackera'), '${d.freeHeapKb} kB'),
      if (d != null && (d.notifyFailed > 0 || d.mtuTooSmall > 0))
        (tr('Błędy wysyłki / za małe MTU'), '${d.notifyFailed} / ${d.mtuTooSmall}'),
      if (trackerLink != null) ...[
        (tr('Historia w trackerze: do wysłania / w drodze'),
            '${trackerLink!.historyUnsent} / ${trackerLink!.historyInflight} (${tr('z')} ${trackerLink!.historyCapacity})'),
        (tr('Historia przywrócona po rozłączeniu'), '${trackerLink!.historyRestored}'),
        (tr('Niewysłane: kolejka pełna / błąd łącza'), '${trackerLink!.queueFull} / ${trackerLink!.notifyErrors}'),
        (tr('Sygnał w trackerze: teraz / min / śr.'),
            '${[trackerLink!.rssiNow, trackerLink!.rssiMin, trackerLink!.rssiAvg].map((v) => v == null ? '–' : '$v').join(' / ')} dBm'),
      ],
    ];
  }
}

/// Pozycja Valkor w postaci używanej przez istniejący filtr i trasę.
/// Dokładność: wartość podana przez tracker (accuracyM); tylko gdy jej nie
/// ma – HDOP × 3 m (ten sam mnożnik co w firmware).
MeshPosition valkorToMesh(ValkorPosition p) {
  final age = p.ageMs;
  return MeshPosition(
    p.lat,
    p.lng,
    altitude: p.altM?.round(),
    time: p.fixTime,
    sentTime: p.fixTime == null || age == null ? null : p.fixTime!.add(Duration(milliseconds: age)),
    timeIsFix: p.fixTime != null,
    speedMs: p.speedMs,
    courseDeg: p.courseDeg,
    sats: p.sats,
    hdop: p.hdop > 0 ? p.hdop : null,
    gpsAccuracyM: 3,
    reportedAccuracyM: p.accuracyM,
    fixValid: p.fixValid,
    fixQuality: p.fixQuality,
    fixId: p.fixId,
    stationary: p.stationary,
  );
}

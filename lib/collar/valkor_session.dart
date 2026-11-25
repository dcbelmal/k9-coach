// Stan połączenia z trackerem z firmware Valkor Track (bezpośredni kanał GPS
// przez Bluetooth). Tworzony, gdy po połączeniu urządzenie ma usługę Valkor;
// bez niej aplikacja działa jak dotąd, tylko przez protokół Meshtastic.
import '../l10n/l10n.dart';
import 'mesh_proto.dart';
import 'valkor_proto.dart';

class ValkorSession {
  /// Usługa Valkor znaleziona w urządzeniu.
  final DateTime detectedAt;
  ValkorSession(this.detectedAt);

  ValkorInfo? info;
  ValkorStatus? status;
  ValkorDiag? diag;
  ValkorAck? lastAck;
  final stats = ValkorLinkStats();

  /// Wersja firmware Valkor i tryb z ostatniego pakietu.
  String? firmware;
  ValkorMode? deviceMode;
  bool insecure = false;
  DateTime? lastRx;

  /// Pozycje Meshtastic tego samego trackera pominięte, bo przychodzą kanałem Valkor.
  int meshIgnored = 0;

  /// Pomiary historyczne odebrane, ale nie wstawione w trasę (starsze niż
  /// bieżąca pozycja – wstawianie w środek trasy: wersja 0.2).
  int historyOutsideTrack = 0;

  /// Urządzenie odpowiada protokołem Valkor (przyszedł poprawny pakiet).
  bool get confirmed => lastRx != null;

  /// Odstęp wysyłki w trybie ustawionym w trackerze (s).
  int? get periodSec => deviceMode?.periodSec;

  /// Rzeczywisty odstęp pomiarów GNSS zmierzony przez tracker (s).
  double? get gnssIntervalSec {
    final d = diag;
    return d == null || d.gnssIntervalAvgMs == 0 ? null : d.gnssIntervalAvgMs / 1000;
  }

  List<String> csvLines() {
    final i = info, d = diag, s = status;
    String n(double? v) => v == null ? '' : v.toStringAsFixed(2);
    return [
      '',
      'valkor;nazwa;wartosc',
      'valkor;firmware;${firmware ?? ''}',
      'valkor;baza_meshtastic;${i?.upstream ?? ''}',
      'valkor;urzadzenie;${i?.hwName ?? ''}',
      'valkor;tryb;${deviceMode?.name ?? ''}',
      'valkor;polaczenie_bez_szyfrowania;$insecure',
      'valkor;pakiety;${stats.packets}',
      'valkor;pozycje_na_zywo;${stats.live}',
      'valkor;pozycje_historyczne;${stats.historical}',
      'valkor;historyczne_poza_trasa;$historyOutsideTrack',
      'valkor;statusy;${stats.status}',
      'valkor;utracone_pakiety;${stats.lost}',
      'valkor;powtorzone_pakiety;${stats.duplicates}',
      'valkor;bledne_ramki;${stats.badFrames}',
      'valkor;restarty_trackera;${stats.restarts}',
      'valkor;mediana_odstepu_odbioru_s;${n(stats.medianLiveInterval)}',
      'valkor;pozycje_meshtastic_pominiete;$meshIgnored',
      if (d != null) ...[
        'valkor;czas_pracy_s;${d.uptimeS}',
        'valkor;gnss_odstep_sr_max_ms;${d.gnssIntervalAvgMs};${d.gnssIntervalMaxMs}',
        'valkor;gnss_pomiary_odrzucone;${d.fixesTotal};${d.fixesRejected}',
        'valkor;wyslane_na_zywo_historia;${d.liveSent};${d.historySent}',
        'valkor;bledy_wysylki_ble;${d.notifyFailed}',
        'valkor;za_male_mtu;${d.mtuTooSmall}',
        'valkor;polaczenia_ponowne_tracker;${d.reconnects}',
        'valkor;historia_w_pamieci_utracona;${d.historyStored};${d.historyDropped}',
        'valkor;rssi_tracker_dbm;${d.rssi}',
        'valkor;wolna_pamiec_kb;${d.freeHeapKb}',
        'valkor;opoznienie_sr_max_ms;${d.latencyAvgMs};${d.latencyMaxMs}',
      ],
      if (s != null) 'valkor;bateria_mv_proc;${s.batteryMv ?? ''};${s.batteryPct ?? ''}',
    ];
  }

  /// Wiersze do ekranu diagnostyki (etykieta, wartość).
  List<(String, String)> rows() {
    final i = info, d = diag;
    String s1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final m = stats.medianLiveInterval;
    return [
      (tr('Firmware'), firmware == null ? '–' : 'Valkor Track $firmware${i == null ? '' : ' (Meshtastic ${i.upstream})'}'),
      if (i != null) (tr('Urządzenie'), i.hwName),
      (tr('Tryb w trackerze'), deviceMode == null ? '–' : deviceMode!.name.toUpperCase()),
      if (insecure) (tr('Uwaga'), tr('połączenie bez szyfrowania – ustaw PIN Bluetooth w trackerze')),
      (tr('Odstęp pomiarów GNSS (zmierzony w trackerze)'), gnssIntervalSec == null ? '–' : tr('~{0} s', [s1(gnssIntervalSec!)])),
      if (d != null) (tr('Najdłuższy odstęp GNSS (ostatnie 10 s)'), tr('{0} s', [s1(d.gnssIntervalMaxMs / 1000)])),
      (tr('Odstęp odbioru pozycji w telefonie'), m == null ? '–' : tr('~{0} s', [s1(m)])),
      if (d != null) (tr('Opóźnienie w trackerze śr. / max'), '${d.latencyAvgMs} / ${d.latencyMaxMs} ms'),
      (tr('Pakiety Valkor / utracone / powtórzone'), '${stats.packets} / ${stats.lost} / ${stats.duplicates}'),
      (tr('Pozycje na żywo / historyczne'), '${stats.live} / ${stats.historical}'),
      if (historyOutsideTrack > 0) (tr('Historyczne poza trasą'), '$historyOutsideTrack'),
      if (stats.badFrames > 0) (tr('Błędne ramki'), '${stats.badFrames}'),
      if (stats.restarts > 0) (tr('Restarty trackera'), '${stats.restarts}'),
      if (d != null) (tr('Sygnał Bluetooth w trackerze'), d.rssi == 0 ? '–' : '${d.rssi} dBm'),
      if (d != null) (tr('Czas pracy trackera'), tr('{0} min', [(d.uptimeS / 60).floor()])),
      if (d != null) (tr('Wolna pamięć trackera'), '${d.freeHeapKb} kB'),
      if (d != null && (d.notifyFailed > 0 || d.mtuTooSmall > 0))
        (tr('Błędy wysyłki / za małe MTU'), '${d.notifyFailed} / ${d.mtuTooSmall}'),
    ];
  }
}

/// Pozycja Valkor w postaci używanej przez istniejący filtr i trasę.
/// Dokładność: firmware liczy HDOP × 3 m – tu ten sam mnożnik.
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
  );
}

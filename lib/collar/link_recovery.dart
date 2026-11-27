// Automatyczne odzyskiwanie łączności z trackerem (0.27.3).
//
// Test terenowy 27.11 (0.27.2 + firmware 0.1.1): po wyłączeniu i włączeniu
// Bluetooth w telefonie aplikacja pokazywała „połączony”, ale przez 329 s nie
// dostała żadnej pozycji. Przyczyny (kod):
//  1. Wtyczka Bluetooth przy wyłączeniu adaptera wysyła tylko zdarzenie
//     dostępności – nie zamyka połączeń GATT i nie zawsze zgłasza rozłączenie.
//     Aplikacja nie słuchała zmian adaptera, więc zostawała w stanie
//     „połączony” na martwym połączeniu.
//  2. Strażnik kanału Valkor umiał tylko ponowić subskrypcję (najwyżej 3 razy
//     na połączenie). Na martwym połączeniu każda subskrypcja kończy się
//     błędem – po trzech próbach nic więcej się nie działo. Brakowało
//     przejścia do pełnego ponownego połączenia.
// Ta klasa podejmuje decyzje (czysta logika, testowalna bez Bluetooth);
// CollarLink je wykonuje.
import 'dart:math' as math;

/// Co zrobić z połączeniem teraz.
enum RecoveryAction {
  none,

  /// Ponowna subskrypcja kanału Valkor (połączenie fizyczne prawdopodobnie żyje).
  resubscribe,

  /// Pełne ponowne połączenie: zamknięcie GATT, nowe połączenie, odkrycie usług.
  reconnect,
}

/// Jedno zakończone odzyskiwanie (do diagnostyki i CSV).
class RecoveryRecord {
  final DateTime lostAt;
  final String why;

  /// Sekundy do fizycznego połączenia Bluetooth i do pierwszej pozycji na żywo
  /// (null = jeszcze nie / nie nastąpiło).
  double? bleSec, positionSec, historySec;
  int attempts = 0;
  RecoveryRecord(this.lostAt, this.why);
}

class LinkRecovery {
  /// Kolejne odstępy ponawiania łączenia (s) w pierwszych [fastPhaseSec]
  /// po utracie, potem [slowSec], a po [verySlowAfterSec] – [verySlowSec].
  static const backoffSec = [1, 2, 3, 5, 8];
  static const fastPhaseSec = 300;
  static const slowSec = 15;
  static const verySlowAfterSec = 900;
  static const verySlowSec = 30;

  /// Po tylu nieudanych odczytach z rzędu (kanał Meshtastic) połączenie
  /// uznajemy za martwe.
  static const readFailLimit = 5;

  /// Po ponownej subskrypcji tyle sekund czekamy na pakiet, zanim zerwiemy
  /// połączenie i połączymy się od nowa (pakiet Status co ~1,5 s w SPORT).
  static const afterResubscribeSec = 4;

  int _step = 0;
  bool adapterOff = false;

  /// Po błędzie „urządzenie nie znalezione” – najpierw krótkie skanowanie.
  bool needScan = false;

  // --- liczniki (cała sesja aplikacji; [resetSession] zeruje) ---
  int attempts = 0, succeeded = 0, failed = 0;
  int resubscribes = 0, forcedReconnects = 0, adapterOffEvents = 0, scans = 0;
  int gatt133 = 0, notFound = 0;
  final List<RecoveryRecord> records = [];
  RecoveryRecord? current;

  /// Łączny czas bez aktualnej pozycji (s) w zakończonych przerwach.
  double noPositionSec = 0;

  /// Odstęp do następnej próby łączenia.
  Duration nextDelay(DateTime now) {
    final lost = current?.lostAt;
    final since = lost == null ? 0 : now.difference(lost).inSeconds;
    final int s;
    if (since >= verySlowAfterSec) {
      s = verySlowSec;
    } else if (since >= fastPhaseSec) {
      s = slowSec;
    } else {
      s = backoffSec[math.min(_step, backoffSec.length - 1)];
      _step++;
    }
    return Duration(seconds: s);
  }

  void resetBackoff() => _step = 0;

  /// Początek przerwy (utrata Bluetooth albo transmisji). Kolejne zgłoszenia
  /// w trakcie tej samej przerwy nic nie zmieniają.
  void onLost(DateTime t, String why) {
    current ??= RecoveryRecord(t, why);
  }

  void onAttempt() {
    attempts++;
    current?.attempts++;
  }

  void onConnectFailed(String? code) {
    failed++;
    if (code == 'deviceNotFound') {
      notFound++;
      needScan = true;
    }
    if (code == 'gatt133') gatt133++;
  }

  /// Połączenie fizyczne Bluetooth gotowe.
  void onConnected(DateTime t) {
    resetBackoff();
    final c = current;
    if (c == null) return;
    succeeded++;
    c.bleSec ??= t.difference(c.lostAt).inMilliseconds / 1000;
  }

  /// Pierwsza pozycja na żywo – koniec przerwy.
  void onLivePosition(DateTime t) {
    final c = current;
    if (c == null) return;
    c.positionSec = t.difference(c.lostAt).inMilliseconds / 1000;
    noPositionSec += c.positionSec!;
    records.add(c);
    if (records.length > 50) records.removeAt(0);
    current = null;
  }

  /// Historia po przerwie pobrana (ostatni pakiet historyczny).
  void onHistoryDone(DateTime t) {
    final r = records.isEmpty ? null : records.last;
    if (r != null && r.historySec == null) r.historySec = t.difference(r.lostAt).inMilliseconds / 1000;
  }

  /// Decyzja strażnika transmisji (wywoływana co sekundę przy połączeniu).
  ///
  /// [valkor] – tracker ma kanał Valkor; [since] – od kiedy liczyć ciszę
  /// (ostatni pakiet w tym połączeniu, a bez niego subskrypcja / wykrycie);
  /// [silentSec] – próg ciszy kanału dla trybu; [subscribeFailed] – błąd
  /// subskrypcji w tym połączeniu; [resubscribedAt] – ostatnia ponowna
  /// subskrypcja w tym połączeniu; [readFails] – nieudane odczyty z rzędu.
  static RecoveryAction decide({
    required DateTime now,
    required bool valkor,
    DateTime? since,
    required double silentSec,
    bool subscribeFailed = false,
    DateTime? resubscribedAt,
    int resubscribes = 0,
    int readFails = 0,
  }) {
    if (readFails >= readFailLimit) return RecoveryAction.reconnect;
    if (!valkor || since == null) return RecoveryAction.none;
    final silent = now.difference(since).inMilliseconds / 1000;
    // Subskrypcja nie działa i od niej nic nie przyszło – połączenie GATT jest
    // martwe (typowe po wyłączeniu Bluetooth): od razu pełne ponowne połączenie.
    if (subscribeFailed && silent >= 2) return RecoveryAction.reconnect;
    if (silent < silentSec + 1) return RecoveryAction.none;
    if (resubscribes == 0) return RecoveryAction.resubscribe;
    final r = resubscribedAt;
    if (r == null || now.difference(r).inMilliseconds / 1000 >= afterResubscribeSec) {
      return RecoveryAction.reconnect;
    }
    return RecoveryAction.none;
  }

  void resetSession() {
    attempts = succeeded = failed = resubscribes = forcedReconnects = adapterOffEvents = scans = 0;
    gatt133 = notFound = 0;
    records.clear();
    noPositionSec = 0;
  }

  /// Wiersze do CSV diagnostyki.
  List<String> csvLines() {
    String n(double? v) => v == null ? '' : v.toStringAsFixed(1);
    double? med(Iterable<double?> xs) {
      final v = xs.whereType<double>().toList()..sort();
      return v.isEmpty ? null : v[v.length ~/ 2];
    }

    return [
      'odzyskiwanie;proby_polaczenia;$attempts',
      'odzyskiwanie;udane_polaczenia;$succeeded',
      'odzyskiwanie;nieudane_polaczenia;$failed',
      'odzyskiwanie;ponowne_subskrypcje;$resubscribes',
      'odzyskiwanie;wymuszone_ponowne_polaczenia;$forcedReconnects',
      'odzyskiwanie;wylaczenia_bluetooth_telefonu;$adapterOffEvents',
      'odzyskiwanie;bledy_133;$gatt133',
      'odzyskiwanie;urzadzenie_nie_znalezione;$notFound',
      'odzyskiwanie;skanowania;$scans',
      'odzyskiwanie;przerwy_zakonczone;${records.length}',
      'odzyskiwanie;mediana_czasu_bluetooth_s;${n(med(records.map((r) => r.bleSec)))}',
      'odzyskiwanie;mediana_czasu_pozycji_s;${n(med(records.map((r) => r.positionSec)))}',
      'odzyskiwanie;czas_bez_aktualnej_pozycji_s;${noPositionSec.toStringAsFixed(1)}',
      'przerwa;poczatek;powod;proby;bluetooth_s;pozycja_s;historia_s',
      for (final r in records)
        'przerwa;${r.lostAt.toIso8601String()};${r.why.replaceAll(';', ',')};${r.attempts};${n(r.bleSec)};${n(r.positionSec)};${n(r.historySec)}',
    ];
  }
}

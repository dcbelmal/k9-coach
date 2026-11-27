import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../collar/collar_link.dart' show FixTrust, TrustEvent, HandlerTrack, PhoneGpsSnapshot;
import '../collar/dog_alerts.dart';
import '../l10n/l10n.dart';
import 'online_services.dart';

/// Stan GPS telefonu (do ekranów i diagnostyki).
enum PhoneGps {
  /// Nikt nie potrzebuje teraz lokalizacji.
  off,

  /// Subskrypcja ruszyła, czekamy na pierwszy pomiar.
  starting,

  /// Świeże pomiary.
  ok,

  /// Pomiary przestały przychodzić.
  stale,

  /// Pomiary przychodzą, ale z dużym błędem.
  inaccurate,

  /// Lokalizacja wyłączona w telefonie.
  serviceOff,

  /// Brak uprawnień do lokalizacji.
  denied,

  /// Inny błąd strumienia lokalizacji.
  error,
}

/// Jedno wspólne źródło lokalizacji telefonu dla treningu i Valkor Track.
///
/// Dlaczego jedno: wtyczka geolocator na Androidzie ma jeden strumień
/// pozycji na całą aplikację. Drugi „getPositionStream” dostaje strumień
/// pierwszego razem z jego ustawieniami – gdy pierwszy był ekran Valkor
/// Track (filtr 3 m, bez usługi w tle), trening nie dostawał usługi
/// pierwszoplanowej ani interwału 1 s i po wygaszeniu ekranu pozycje
/// stawały na minuty. Tutaj jest jedna subskrypcja, a jej ustawienia
/// wynikają z tego, kto jej potrzebuje.
///
/// * Bez filtra odległości i z interwałem 1 s – pomiary także na postoju.
/// * Usługa pierwszoplanowa (powiadomienie) – pomiary przy wygaszonym ekranie.
/// * Strażnik: gdy przez [restartAfterSec] nie ma pomiaru, subskrypcja jest
///   uruchamiana od nowa (najwyżej raz na [restartBackoffSec] s, z rosnącą
///   przerwą), a przyczyna trafia do diagnostyki.
class PhoneLocation extends ChangeNotifier with WidgetsBindingObserver {
  PhoneLocation._();
  static final PhoneLocation instance = PhoneLocation._();

  /// Po tylu sekundach bez pomiaru pozycja telefonu jest nieaktualna.
  static const staleSec = 5.0;

  /// Po tylu sekundach bez pomiaru uruchamiamy subskrypcję od nowa.
  /// (W 0.25.0 było 12 s; przerwa widziana w teście = ten próg + do 1 s
  /// sprawdzania + czas od restartu do pierwszego pomiaru, razem ~15 s.)
  static const restartAfterSec = 8.0;

  /// Przerwa krótsza niż tyle sekund nie trafia na listę przerw.
  static const gapLogSec = 3.0;

  /// Przez tyle sekund po starcie / restarcie subskrypcji przerwy liczymy
  /// jako „inicjalizację”, a nie przerwy w aktywnym śledzeniu.
  static const initWindowSec = 30.0;

  /// Najkrótsza przerwa między restartami (s); rośnie do [restartMaxSec].
  static const restartBackoffSec = 15.0;
  static const restartMaxSec = 120.0;

  /// Pomiar z błędem większym niż tyle metrów nie służy do odległości.
  static const maxAccuracyM = 40.0;

  /// Telefon podaje dokładność gorszą niż tyle (m) – „Niska dokładność
  /// lokalizacji” zamiast liczby metrów do psa.
  static const weakAccuracyM = 20.0;

  /// Strumień pozycji (podmieniany w testach).
  @visibleForTesting
  static Stream<Position> Function(LocationSettings s) streamFactory =
      (s) => Geolocator.getPositionStream(locationSettings: s);

  /// Zegar (podmieniany w testach).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  final Map<String, _Client> _clients = {};
  StreamSubscription<Position>? _sub;
  String? _key;
  Timer? _watchdog;
  bool _observing = false;
  final _out = StreamController<Position>.broadcast();

  /// Każdy pomiar telefonu (także na postoju i z dużym błędem).
  Stream<Position> get positions => _out.stream;

  /// Ostatni pomiar i chwila jego odbioru.
  Position? last;
  DateTime? lastAt;

  /// Ostatni pomiar dość dokładny do liczenia odległości.
  Position? lastGood;

  PhoneGps state = PhoneGps.off;
  String? lastError;

  /// Diagnostyka: liczba pomiarów, restartów subskrypcji, odstępy między
  /// pomiarami (ostatnie 120) i najdłuższa przerwa w tej sesji.
  int updates = 0;
  int restarts = 0;
  DateTime? lastRestartAt;
  String? lastRestartReason;
  final List<double> intervals = [];
  double maxGapSec = 0;

  /// Najdłuższa przerwa osobno: przy uruchamianiu / ustalaniu pozycji
  /// i w aktywnym śledzeniu (pozycja już wiarygodna).
  double maxGapInitSec = 0, maxGapTrackingSec = 0;

  /// Przerwy dłuższe niż [gapLogSec] (ostatnie 50).
  final List<PhoneGap> gaps = [];

  /// Czas od ostatniego restartu subskrypcji do pierwszego pomiaru (s).
  double? lastRestartLatencySec;
  bool _awaitFirstAfterRestart = false;

  /// Stabilizacja pozycji telefonu (seria spójnych, dokładnych pomiarów).
  final trust = FixTrust.phone();

  /// Pozycję telefonu trzeba ustalić od nowa (np. start treningu).
  void restabilize(String why) {
    trust.reset(why, clock());
    notifyListeners();
  }
  DateTime? startedAt;
  double _backoff = restartBackoffSec;
  DateTime? _subAt;

  bool get active => _clients.isNotEmpty;
  bool get background => _clients.values.any((c) => c.background);

  /// Wiek ostatniego pomiaru (s), null = brak.
  double? ageSec([DateTime? now]) {
    final t = lastAt;
    return t == null ? null : (now ?? clock()).difference(t).inMilliseconds / 1000;
  }

  /// Czy mamy świeży i dość dokładny pomiar.
  bool fresh([DateTime? now]) {
    final a = ageSec(now);
    return a != null && a <= staleSec && last != null && last!.accuracy <= maxAccuracyM;
  }

  /// Rzeczywisty odstęp między pomiarami (mediana), null = za mało danych.
  double? get medianInterval {
    if (intervals.length < 3) return null;
    final s = [...intervals]..sort();
    return s[s.length ~/ 2];
  }

  /// Dlaczego nie ma aktualnej lokalizacji (null = jest).
  String? reason([DateTime? now]) {
    switch (state) {
      case PhoneGps.off:
        return tr('lokalizacja telefonu nie jest włączona w tym ekranie');
      case PhoneGps.serviceOff:
        return tr('lokalizacja (GPS) wyłączona w telefonie');
      case PhoneGps.denied:
        return tr('brak uprawnień do lokalizacji');
      case PhoneGps.error:
        return tr('błąd lokalizacji: {0}', [lastError ?? '?']);
      case PhoneGps.starting:
        return tr('czekam na pierwszy pomiar GPS telefonu');
      case PhoneGps.inaccurate:
        return tr('GPS telefonu ma duży błąd (~{0} m)', [last?.accuracy.round() ?? '?']);
      case PhoneGps.stale:
        return tr('brak nowego pomiaru GPS telefonu od {0} s', [(ageSec(now) ?? 0).round()]);
      case PhoneGps.ok:
        return fresh(now) ? null : tr('brak nowego pomiaru GPS telefonu od {0} s', [(ageSec(now) ?? 0).round()]);
    }
  }

  /// Stan do wskaźnika „GPS telefonu” (null = lokalizacja nieużywana).
  PhoneGpsSnapshot? snapshot([DateTime? now]) {
    if (state == PhoneGps.off) return null;
    return PhoneGpsSnapshot(
      problem: reason(now),
      trusted: trust.stable,
      why: trust.why,
      accuracyM: last?.accuracy,
    );
  }

  /// Zgłasza potrzebę lokalizacji. [background] = ma działać przy wygaszonym
  /// ekranie (usługa pierwszoplanowa z powiadomieniem [title] / [text]).
  Future<void> acquire(String id, {bool background = true, String? title, String? text}) async {
    if (!active) trust.reset(tr('uruchomienie lokalizacji'), clock());
    _clients[id] = _Client(background, title, text);
    _observe();
    await _serial(_apply);
  }

  /// Zmiany subskrypcji jedna po drugiej – dwa równoczesne starty nie mogą
  /// zostawić dwóch subskrypcji.
  Future<void> _queue = Future.value();
  Future<void> _serial(Future<void> Function() op) {
    final f = _queue.then((_) => op());
    _queue = f.catchError((_) {});
    return f;
  }

  /// Zwalnia lokalizację. Gdy nikt jej nie potrzebuje – subskrypcja stop.
  Future<void> release(String id) async {
    if (_clients.remove(id) == null) return;
    await _serial(_apply);
  }

  void _observe() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Powrót do aplikacji: gdy pomiary stoją – od razu nowa subskrypcja.
    if (state == AppLifecycleState.resumed && active) {
      final a = ageSec();
      if (a == null || a > restartAfterSec) unawaited(restart(tr('powrót do aplikacji bez świeżej pozycji')));
    }
  }

  String _keyFor() {
    if (!background) return 'fg';
    final c = _clients.values.firstWhere((c) => c.background);
    return 'bg|${c.title}';
  }

  Future<void> _apply() async {
    if (!active) {
      await _stop();
      state = PhoneGps.off;
      notifyListeners();
      return;
    }
    final k = _keyFor();
    if (_sub != null && k == _key) return;
    await _start(k);
  }

  Future<void> _stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    final s = _sub;
    _sub = null;
    _key = null;
    await s?.cancel();
  }

  Future<void> _start(String k) async {
    await _stop();
    _key = k;
    if (!await _permitted()) {
      _key = null;
      _armWatchdog();
      notifyListeners();
      return;
    }
    startedAt ??= clock();
    _subAt = clock();
    if (state != PhoneGps.ok && state != PhoneGps.inaccurate) state = lastAt == null ? PhoneGps.starting : PhoneGps.stale;
    try {
      _sub = streamFactory(_settings()).listen(_onPosition, onError: _onError);
    } catch (e) {
      _onError(e);
    }
    _armWatchdog();
    notifyListeners();
  }

  Future<bool> _permitted() async {
    if (kIsWeb) {
      state = PhoneGps.error;
      lastError = tr('tylko w aplikacji na telefonie');
      return false;
    }
    try {
      if (!await GpsServices.serviceEnabled()) {
        state = PhoneGps.serviceOff;
        return false;
      }
      final p = await GpsServices.checkPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
        state = PhoneGps.denied;
        return false;
      }
    } catch (e) {
      state = PhoneGps.error;
      lastError = e.toString();
      return false;
    }
    return true;
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Strażnik (co sekundę): oznacza brak pomiarów i w razie potrzeby
  /// uruchamia subskrypcję od nowa.
  @visibleForTesting
  void tick([DateTime? now]) {
    if (!active) return;
    final t = now ?? clock();
    final la = lastAt, sa = _subAt;
    final since = la == null ? sa : (sa == null || la.isAfter(sa) ? la : sa);
    final quiet = since == null ? 0.0 : t.difference(since).inMilliseconds / 1000;
    final age = la == null ? null : t.difference(la).inMilliseconds / 1000;
    if (age != null && age > staleSec && (state == PhoneGps.ok || state == PhoneGps.inaccurate)) {
      state = PhoneGps.stale;
      notifyListeners();
    }
    final lastR = lastRestartAt;
    final waited = lastR == null ? double.infinity : t.difference(lastR).inMilliseconds / 1000;
    final noSub = _sub == null;
    if ((noSub || quiet > restartAfterSec) && waited >= _backoff) {
      final why = noSub
          ? (reason(t) ?? tr('subskrypcja nieaktywna'))
          : tr('brak pomiaru od {0} s', [quiet.round()]);
      unawaited(restart(why, now: t));
    }
  }

  /// Uruchamia subskrypcję od nowa (licznik restartów, rosnąca przerwa).
  Future<void> restart(String why, {DateTime? now}) async {
    if (!active) return;
    final t = now ?? clock();
    restarts++;
    lastRestartAt = t;
    _awaitFirstAfterRestart = true;
    lastRestartReason = why;
    _backoff = (_backoff * 2).clamp(restartBackoffSec, restartMaxSec);
    await _serial(() async {
      if (active) await _start(_keyFor());
    });
  }

  void _onError(Object e) {
    if (e is LocationServiceDisabledException) {
      state = PhoneGps.serviceOff;
    } else if (e is PermissionDeniedException) {
      state = PhoneGps.denied;
    } else {
      state = PhoneGps.error;
      lastError = e.toString();
    }
    notifyListeners();
  }

  /// Nowy pomiar telefonu (wywoływany przez strumień; publiczny dla testów).
  @visibleForTesting
  void onPosition(Position p, {DateTime? now}) => _onPosition(p, now: now);

  void _onPosition(Position p, {DateTime? now}) {
    final t = now ?? clock();
    final prev = lastAt;
    final sa = _subAt;
    final init = !trust.stable || (sa != null && t.difference(sa).inMilliseconds / 1000 <= initWindowSec);
    if (prev != null) {
      final gap = t.difference(prev).inMilliseconds / 1000;
      if (gap > 0) {
        intervals.add(gap);
        if (intervals.length > 120) intervals.removeAt(0);
        if (gap > maxGapSec) maxGapSec = gap;
        if (init) {
          if (gap > maxGapInitSec) maxGapInitSec = gap;
        } else if (gap > maxGapTrackingSec) {
          maxGapTrackingSec = gap;
        }
        if (gap >= gapLogSec) {
          gaps.add(PhoneGap(t, gap, init, _awaitFirstAfterRestart));
          if (gaps.length > 50) gaps.removeAt(0);
        }
      }
    }
    if (_awaitFirstAfterRestart && lastRestartAt != null) {
      lastRestartLatencySec = t.difference(lastRestartAt!).inMilliseconds / 1000;
      _awaitFirstAfterRestart = false;
    }
    updates++;
    last = p;
    lastAt = t;
    _backoff = restartBackoffSec;
    final good = p.accuracy > 0 && p.accuracy <= maxAccuracyM;
    state = good ? PhoneGps.ok : PhoneGps.inaccurate;
    // Wiarygodność: seria spójnych pomiarów (czas pomiaru z GPS, gdy rozsądny).
    final ft = p.timestamp.toLocal();
    final fixT = ft.isAfter(t) || t.difference(ft).inSeconds > 600 ? t : ft;
    final ev = trust.add(LatLng(p.latitude, p.longitude), fixT, accuracyM: p.accuracy, speedMs: p.speed >= 0 ? p.speed : null);
    // Skok albo nowa seria: filtr pozycji telefonu zaczyna od nowa w nowym
    // miejscu (zamiast wlec się ~25 s za starą, błędną pozycją).
    if (ev == TrustEvent.jump || ev == TrustEvent.start) HandlerTrack.instance.resetFilter();
    if (good) {
      lastGood = p;
      // Historia pozycji telefonu do porównań z psem – z prawdziwym czasem pomiaru.
      DogAlerts.instance.setHandler(LatLng(p.latitude, p.longitude),
          accuracyM: p.accuracy, at: p.timestamp, speedMs: p.speed, now: t);
    }
    _out.add(p);
    notifyListeners();
  }

  LocationSettings _settings() {
    final bg = _clients.values.where((c) => c.background).firstOrNull;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: bg == null
            ? null
            : ForegroundNotificationConfig(
                notificationTitle: bg.title ?? tr('Valkor Coach'),
                notificationText: bg.text ?? tr('Lokalizacja działa w tle. Możesz wyłączyć ekran.'),
                notificationChannelName: tr('Trening GPS'),
                enableWakeLock: true,
                setOngoing: true,
                notificationIcon: const AndroidResource(name: 'ic_stat_valkor', defType: 'drawable'),
              ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: bg != null,
        allowBackgroundLocationUpdates: bg != null,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
  }

  /// Wiersze do eksportu CSV (sekcja GPS telefonu).
  List<String> csvLines([DateTime? now]) {
    String n(double? v) => v == null ? '' : v.toStringAsFixed(1);
    return [
      'gps_telefonu;pomiary;$updates',
      'gps_telefonu;odstep_mediana_s;${n(medianInterval)}',
      'gps_telefonu;najdluzsza_przerwa_s;${n(maxGapSec)}',
      'gps_telefonu;najdluzsza_przerwa_inicjalizacja_s;${n(maxGapInitSec)}',
      'gps_telefonu;najdluzsza_przerwa_sledzenie_s;${n(maxGapTrackingSec)}',
      'gps_telefonu;czas_od_restartu_do_pomiaru_s;${n(lastRestartLatencySec)}',
      'gps_telefonu;pozycja_wiarygodna;${trust.stable ? 1 : 0};${trust.why ?? ''}',
      'gps_telefonu;stabilizacje;${trust.stabilizations};skoki;${trust.jumps}',
      for (final g in gaps)
        'gps_telefonu;przerwa;${g.endAt.toIso8601String()};${n(g.sec)};${g.init ? 'inicjalizacja' : 'sledzenie'};${g.afterRestart ? 'po_restarcie' : ''}',
      'gps_telefonu;restarty_subskrypcji;$restarts',
      'gps_telefonu;ostatni_restart;${lastRestartAt?.toIso8601String() ?? ''};${lastRestartReason ?? ''}',
      'gps_telefonu;stan;${state.name};${reason(now) ?? ''}',
    ];
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _clients.clear();
    _queue = Future.value();
    await _stop();
    last = lastGood = null;
    lastAt = lastRestartAt = startedAt = _subAt = null;
    lastRestartReason = lastError = null;
    state = PhoneGps.off;
    updates = restarts = 0;
    intervals.clear();
    maxGapSec = maxGapInitSec = maxGapTrackingSec = 0;
    gaps.clear();
    lastRestartLatencySec = null;
    _awaitFirstAfterRestart = false;
    trust.reset('');
    _backoff = restartBackoffSec;
    streamFactory = (s) => Geolocator.getPositionStream(locationSettings: s);
    clock = DateTime.now;
  }
}

class _Client {
  final bool background;
  final String? title, text;
  const _Client(this.background, this.title, this.text);
}

/// Przerwa w pomiarach GPS telefonu (do diagnostyki).
class PhoneGap {
  final DateTime endAt;
  final double sec;

  /// true = przy uruchamianiu / ustalaniu pozycji, false = w aktywnym śledzeniu.
  final bool init;

  /// Przerwę zakończył restart subskrypcji.
  final bool afterRestart;
  const PhoneGap(this.endAt, this.sec, this.init, this.afterRestart);
}

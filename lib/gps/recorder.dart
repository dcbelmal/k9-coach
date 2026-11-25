import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../collar/collar_link.dart';
import '../collar/tracker_driver.dart';
import '../collar/fix_filter.dart' show FixSource;
import 'dog_track_builder.dart';
import '../dogs/dog_profiles.dart';
import '../models.dart';
import '../storage/safe_prefs.dart';
import 'gps_drafts.dart';
import 'online_services.dart';
import 'phone_location.dart';
import '../notifications.dart';
import '../theme.dart' show fmtKm;
import 'track.dart';
import '../l10n/l10n.dart';

enum RecState { idle, running, paused }

/// Nagrywanie treningu z GPS (działa też przy wyłączonym ekranie dzięki usłudze w tle).
class TrackRecorder extends ChangeNotifier {
  TrackRecorder._();
  static final TrackRecorder instance = TrackRecorder._();

  RecState state = RecState.idle;
  Discipline discipline = Discipline.canicross;
  bool voice = true;
  int waterEveryMin = 0;

  /// Gdy false – liczymy tylko czas (dyscypliny bez dystansu, np. IGP).
  bool useGps = true;

  /// Cel czasu w minutach (0 = bez celu) i opcjonalny cel dystansu.
  int targetMin = 0;
  double? targetKm;

  /// Trening z planu, który właśnie wykonujemy.
  TrainingSession? plan;
  bool targetTimeDone = false;
  bool targetKmDone = false;
  int _lastNotif = -100;

  final _watch = Stopwatch();
  DateTime? startedAt;
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  final FlutterTts _tts = FlutterTts();

  List<List<TrackPoint>> segments = [];
  List<double> laps = [];

  /// Trasa psa z obroży GPS (T1000-E): surowe pomiary, punkty trasy i dystans
  /// (patrz [DogTrackBuilder]). Segmenty: nowy po pauzie, po utracie
  /// wiarygodności i po przerwie w pomiarach dłuższej niż próg trybu trackera
  /// (Valkor SPORT 5 s, WALK 12 s, ECO 45 s; zwykły Meshtastic [dogGapSec]).
  final dogTrack = DogTrackBuilder(gapSec: dogGapSec.toDouble());
  List<List<TrackPoint>> get dogSegments => dogTrack.segments;
  set dogSegments(List<List<TrackPoint>> v) {
    dogTrack.clear();
    dogTrack.segments = v;
  }

  double get dogMeters => dogTrack.meters;
  set dogMeters(double v) => dogTrack.meters = v;
  CollarFix? dogLast;

  /// Tracker, którego pozycje zapisujemy – ustalany na starcie i niezmienny
  /// do końca treningu (zmiana wyboru w trakcie nie przełącza źródła).
  int? dogNode;

  /// Przerwa w pomiarach psa (s) dla zwykłego Meshtastic, po której zaczynamy nowy segment.
  static const dogGapSec = 90;

  /// Odcinki ruchu treningu w czasie zegarowym (do umieszczenia pomiaru psa
  /// – także historycznego – w czasie treningu; pomiary z pauzy pomijamy).
  final List<_Span> _spans = [];
  DateTime? _legacyZero;

  /// Czas treningu (s ruchu) dla chwili [wall]; null = pauza / przed startem.
  @visibleForTesting
  double? secondsAt(DateTime wall, {DateTime? now}) {
    if (_spans.isEmpty) {
      // Bez startu (testy): czas od pierwszego pomiaru, tylko w trakcie ruchu.
      if (state != RecState.running) return null;
      final z = _legacyZero ??= wall;
      final v = wall.difference(z).inMilliseconds / 1000;
      return v < 0 ? 0 : v;
    }
    for (final sp in _spans.reversed) {
      if (wall.isBefore(sp.wall)) continue;
      final end = sp.end;
      if (end != null && wall.isAfter(end)) return null; // w pauzie po tym odcinku
      final v = sp.t + wall.difference(sp.wall).inMilliseconds / 1000;
      // Zegar trackera minimalnie przed zegarem telefonu – nie dalej niż „teraz”.
      if (end == null && wall.isAfter(now ?? clock())) return sp.t + (now ?? clock()).difference(sp.wall).inMilliseconds / 1000;
      return v;
    }
    return null;
  }

  /// Zegar (podmieniany w testach).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Udaje start treningu w chwili [t] (testy trasy psa i historii).
  @visibleForTesting
  void startClockForTest(DateTime t) {
    state = RecState.running;
    startedAt = t;
    _spans
      ..clear()
      ..add(_Span(t, 0));
    dogTrack.clear();
    dogLast = null;
  }

  /// Udaje pauzę / wznowienie w chwili [t] (testy).
  @visibleForTesting
  void pauseAtForTest(DateTime t) {
    state = RecState.paused;
    if (_spans.isNotEmpty) _spans.last.end = t;
  }

  @visibleForTesting
  void resumeAtForTest(DateTime t) {
    final last = _spans.last;
    final tPrev = last.t + last.end!.difference(last.wall).inMilliseconds / 1000;
    _spans.add(_Span(t, tPrev));
    state = RecState.running;
  }

  /// Numer odcinka ruchu dla chwili [wall] (zmienia się po pauzie).
  int _spanOf(DateTime wall) {
    for (var i = _spans.length - 1; i >= 0; i--) {
      if (!wall.isBefore(_spans[i].wall)) return i;
    }
    return 0;
  }

  List<TrackPoint> get dogPoints => [for (final s in dogSegments) ...s];
  StreamSubscription<CollarFix>? _dogSub;
  double meters = 0;
  double? currentSpeedKmh;
  Position? last;
  String? error;
  int _announcedKm = 0;
  double _kmStartT = 0;
  double _lastLapT = 0;
  double _lastLapM = 0;
  int _waterCount = 0;

  /// Sesja i pies ustalone w chwili startu – trening zapisze się u tego psa,
  /// nawet jeśli w międzyczasie ktoś przełączy psa.
  String? sessionId;
  String? dogId;
  double _lastDraftT = -100;

  /// Co ile sekund zapisujemy szkic trwającego treningu.
  static const draftEverySec = 15;

  double get seconds => _watch.elapsedMilliseconds / 1000;

  /// Bieżący stan jako szkic (do zapisu i finalizacji).
  GpsDraft draft() => GpsDraft(
        sessionId: sessionId ?? 's${DateTime.now().microsecondsSinceEpoch}',
        dogId: dogId ?? DogProfiles.instance.activeId,
        discipline: discipline,
        startedAt: startedAt ?? DateTime.now(),
        seconds: seconds,
        segments: [for (final s in segments) [...s]],
        laps: [...laps],
        dogSegments: [for (final s in dogSegments) [...s]],
        useGps: useGps,
        planId: plan?.id,
        rpe: plan?.rpe ?? 5,
        notes: plan?.notes ?? '',
      );

  final _draftQueue = SerialQueue();

  Future<void> _saveDraft() {
    _lastDraftT = seconds;
    final d = draft();
    return _draftQueue.run(() async {
      if (state == RecState.idle) return; // po zakończeniu szkic zapisuje już finalizacja
      try {
        await GpsDrafts.save(d);
      } catch (e) {
        logError('Szkic treningu', e);
      }
    });
  }

  /// Czeka, aż zapiszą się szkice w toku.
  Future<void> flushDrafts() => _draftQueue.run(() async {});
  double get avgPace => meters < 20 ? 0 : seconds / meters * 1000;
  double get avgSpeedKmh => seconds <= 0 ? 0 : meters / seconds * 3.6;
  double get lapSeconds => seconds - _lastLapT;
  double get lapMeters => meters - _lastLapM;
  List<LatLng> get allPoints => [for (final s in segments) for (final p in s) p.ll];

  /// Sprawdza GPS i uprawnienia. Zwraca komunikat błędu albo null.
  static Future<String?> ensurePermission() async {
    if (kIsWeb) return tr('Trening GPS działa tylko w aplikacji na telefonie.');
    if (!await GpsServices.serviceEnabled()) return tr('Włącz lokalizację (GPS) w telefonie.');
    var p = await GpsServices.checkPermission();
    if (p == LocationPermission.denied) p = await GpsServices.requestPermission();
    if (p == LocationPermission.denied) return tr('Bez dostępu do lokalizacji nie da się nagrać trasy.');
    if (p == LocationPermission.deniedForever) {
      return tr('Dostęp do lokalizacji jest zablokowany. Włącz go w ustawieniach telefonu dla Valkor Coach.');
    }
    return null;
  }

  /// Klient wspólnego źródła lokalizacji ([PhoneLocation]).
  static const locationClient = 'training';

  Future<void> start() async {
    // Nigdy dwa nagrania naraz: drugi start nie może wyzerować trwającej sesji.
    if (state != RecState.idle) return;
    segments = [[]];
    laps = [];
    meters = 0;
    dogTrack.clear();
    dogLast = null;
    dogNode = TrackerDrivers.active.dogNode;
    last = null;
    error = null;
    _announcedKm = 0;
    _kmStartT = 0;
    _lastLapT = 0;
    _lastLapM = 0;
    _waterCount = 0;
    targetTimeDone = false;
    targetKmDone = false;
    _lastNotif = -100;
    currentSpeedKmh = null;
    startedAt = DateTime.now();
    _spans
      ..clear()
      ..add(_Span(startedAt!, 0));
    _legacyZero = null;
    sessionId = 's${startedAt!.microsecondsSinceEpoch}';
    dogId = DogProfiles.instance.activeId;
    _lastDraftT = -100;
    _watch
      ..reset()
      ..start();
    state = RecState.running;
    try {
      await _tts.setLanguage(L10n.instance.ttsLocale);
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
    await Notifications.instance.requestPermission();
    if (useGps) {
      _listen();
      // Start treningu: gdy pozycja telefonu nie jest jeszcze wiarygodna,
      // punkty i dystans liczą się dopiero po jej ustaleniu (bez sztywnego
      // czekania, gdy już jest wiarygodna).
      _phoneEpoch = PhoneLocation.instance.trust.stabilizations;
      _dogSub?.cancel();
      _dogSub = TrackerDrivers.active.fixes.listen(onDogFix);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_saveDraft());
    _scheduleGoal();
    _updateNotification();
    notifyListeners();
    if (voice) {
      _say(tr('Start. Trening {0}.{1}', [discipline.label, targetMin > 0 ? tr(' Cel: {0} {1}.', [targetMin, _minWord(targetMin)]) : '']));
    }
  }

  /// Lokalizacja ze wspólnego źródła – jedna subskrypcja GPS dla treningu
  /// i Valkor Track (z usługą w tle, co 1 s, bez filtra odległości).
  void _listen() {
    _sub?.cancel();
    final loc = PhoneLocation.instance;
    _sub = loc.positions.listen(onPosition);
    loc.removeListener(_onLocState);
    loc.addListener(_onLocState);
    unawaited(loc.acquire(locationClient,
        title: tr('Valkor Coach – trening {0}', [discipline.label]), text: tr('Nagrywam trasę. Możesz wyłączyć ekran.')));
  }

  void _onLocState() {
    if (state == RecState.idle) return;
    final loc = PhoneLocation.instance;
    final e = switch (loc.state) {
      PhoneGps.serviceOff => tr('Włącz lokalizację (GPS) w telefonie.'),
      PhoneGps.denied => tr('Brak dostępu do lokalizacji'),
      PhoneGps.stale || PhoneGps.error => tr('Brak sygnału GPS'),
      _ => null,
    };
    if (e != error) {
      error = e;
      notifyListeners();
    }
  }

  int _phoneEpoch = -1;

  /// Prędkość starsza niż tyle sekund nie jest już „bieżąca”.
  static const speedMaxAgeSec = 5;
  DateTime? _speedAt;

  /// Dystans liczony od punktu kotwicy (ostatniego dodanego), więc wolny
  /// marsz nie ginie, a dryf na postoju nie dodaje metrów.
  /// Próg: postój (prędkość z GPS < 0,5 m/s) – co najmniej błąd pozycji
  /// (min. 3 m); w ruchu – połowa błędu, od 2 do 5 m.
  static double moveThresholdM(double accuracyM, double? speedMs) {
    final acc = accuracyM > 0 ? accuracyM : 10.0;
    final still = speedMs != null && speedMs >= 0 && speedMs < 0.5;
    return still ? math.max(3.0, acc) : (acc * 0.5).clamp(2.0, 5.0);
  }

  @visibleForTesting
  void onPosition(Position p) {
    if (state != RecState.running) return;
    final seg = segments.last;
    // Prędkość bieżąca – także na postoju (0), nie tylko gdy dodajemy punkt.
    if (p.speed >= 0 && p.accuracy <= 40) {
      currentSpeedKmh = p.speed < 0.5 ? 0 : p.speed * 3.6;
      _speedAt = DateTime.now();
    }
    if (p.accuracy > (seg.isEmpty ? 40 : 25)) {
      notifyListeners();
      return; // za słaby sygnał
    }
    // Stabilizacja: niewiarygodnych pozycji (start, wyjście z budynku,
    // powrót GPS po przerwie) nie zapisujemy i nie liczymy z nich dystansu.
    final trust = PhoneLocation.instance.trust;
    if (!trust.stable) {
      last = p;
      notifyListeners();
      return;
    }
    // Pozycja ustalona od nowa (po skoku lub przerwie): nowy odcinek trasy,
    // bez dystansu „przez skok”.
    if (trust.stabilizations != _phoneEpoch) {
      _phoneEpoch = trust.stabilizations;
      if (seg.isNotEmpty) {
        segments.add([]);
        onPosition(p);
        return;
      }
    }
    final t = seconds;
    if (seg.isNotEmpty) {
      final prev = seg.last;
      final d = const Distance()(prev.ll, LatLng(p.latitude, p.longitude));
      final dt = t - prev.t;
      if (dt <= 0 && d > 10) return; // dwa odczyty w tej samej chwili daleko od siebie – błąd
      if (dt > 0 && d / dt > 16) return; // skok GPS (>57 km/h)
      final speed = p.speed >= 0 ? p.speed : null;
      if (d < moveThresholdM(p.accuracy, speed)) {
        last = p;
        notifyListeners();
        return;
      }
      meters += d;
      if (p.speed < 0) {
        currentSpeedKmh = dt > 0 ? d / dt * 3.6 : null;
        _speedAt = DateTime.now();
      }
    }
    seg.add(TrackPoint(p.latitude, p.longitude, t, p.speed >= 0 ? p.speed : null));
    last = p;
    _checkKm();
    notifyListeners();
  }

  /// Pozycja psa z obroży. Pauza nie zatrzymuje obroży – pomiary z pauzy
  /// nie trafiają do trasy. Pomiar historyczny (odzyskany z pamięci trackera
  /// po utracie zasięgu) trafia w swoje miejsce w czasie treningu, a trasa
  /// i dystans są przeliczane; nie zmienia bieżącej pozycji ([dogLast]).
  @visibleForTesting
  void onDogFix(CollarFix f) {
    if (state == RecState.idle) return;
    // Źródło ustalone na starcie; gdy tracker nie był jeszcze znany – pierwszy pies.
    dogNode ??= TrackerDrivers.active.dogNode;
    if (f.node != dogNode) return;
    // Pomiar sprzed startu treningu (np. zaległy z kolejki albo z poprzedniego
    // treningu) nie należy do tej trasy ani dystansu.
    final st = startedAt;
    if (st != null && f.fixAt.isBefore(st)) return;
    if (!f.historical) dogLast = f;
    dogTrack.gapSec = f.source == FixSource.meshtastic
        ? dogGapSec.toDouble()
        : CollarLink.instance.valkorLimits.trackGapSec;
    final live = !f.historical;
    // Pomiar na żywo w czasie pauzy: bez punktu (i przerwa w odcinku).
    final t = live && state != RecState.running ? null : secondsAt(f.fixAt);
    dogTrack.add(DogSample(f.fixAt, t, _spanOf(f.fixAt), f.lat, f.lng,
        speedMs: f.speedMs, accuracyM: f.accuracyM, source: f.source, trusted: f.trusted));
    notifyListeners();
  }

  void _checkKm() {
    final km = meters ~/ 1000;
    if (km > _announcedKm) {
      _announcedKm = km;
      final kmTime = seconds - _kmStartT;
      _kmStartT = seconds;
      HapticFeedback.mediumImpact();
      if (voice) {
        _say(tr('Kilometr {0}. Czas {1}. Tempo ostatniego kilometra {2}.', [km, _spoken(seconds), _spoken(kmTime)]));
      }
    }
    if (targetKm != null && targetKm! > 0 && !targetKmDone && meters >= targetKm! * 1000) {
      targetKmDone = true;
      HapticFeedback.heavyImpact();
      _say(tr('Cel dystansu osiągnięty. {0} kilometra. Brawo!', [fmtKm(targetKm!)]));
    }
  }

  void _tick() {
    if (state != RecState.running) return;
    if (targetMin > 0 && !targetTimeDone && seconds >= targetMin * 60) {
      targetTimeDone = true;
      HapticFeedback.heavyImpact();
      _say(tr('Cel osiągnięty. {0} {1} treningu. Brawo!', [targetMin, _minWord(targetMin)]));
    }
    // Prędkość bez świeżego pomiaru nie jest bieżąca – pokazujemy „–”.
    final sa = _speedAt;
    if (currentSpeedKmh != null && (sa == null || DateTime.now().difference(sa).inSeconds > speedMaxAgeSec)) {
      currentSpeedKmh = null;
    }
    if (seconds - _lastNotif >= 10) _updateNotification();
    if (seconds - _lastDraftT >= draftEverySec) unawaited(_saveDraft());
    if (waterEveryMin > 0) {
      final n = seconds ~/ (waterEveryMin * 60);
      if (n > _waterCount) {
        _waterCount = n;
        HapticFeedback.heavyImpact();
        _say(tr('Czas na wodę dla psa.'));
      }
    }
    notifyListeners();
  }

  void pause() {
    if (state != RecState.running) return;
    _watch.stop();
    if (_spans.isNotEmpty && _spans.last.end == null) _spans.last.end = DateTime.now();
    state = RecState.paused;
    currentSpeedKmh = null;
    unawaited(_saveDraft());
    Notifications.instance.cancel(Notifications.goalId);
    _updateNotification();
    if (voice) _say(tr('Pauza.'));
    notifyListeners();
  }

  void resume() {
    if (state != RecState.paused) return;
    _watch.start();
    _spans.add(_Span(DateTime.now(), seconds));
    segments.add([]);
    state = RecState.running;
    _scheduleGoal();
    _updateNotification();
    if (voice) _say(tr('Wznawiam.'));
    notifyListeners();
  }

  void lap() {
    if (state == RecState.idle) return;
    laps.add(seconds);
    final lt = seconds - _lastLapT;
    final lm = meters - _lastLapM;
    _lastLapT = seconds;
    _lastLapM = meters;
    HapticFeedback.mediumImpact();
    if (voice) {
      _say(tr('Okrążenie {0}. {1}{2}.', [laps.length, _spoken(lt), lm > 50 ? tr(', {0} kilometra', [(lm / 1000).toStringAsFixed(2).replaceAll('.', ' ${tr('przecinek')} ')]) : '']));
    }
    notifyListeners();
  }

  /// Kończy nagrywanie i zwraca trasę.
  Future<Track> stop() async {
    _watch.stop();
    await _sub?.cancel();
    _sub = null;
    PhoneLocation.instance.removeListener(_onLocState);
    await PhoneLocation.instance.release(locationClient);
    await _dogSub?.cancel();
    _dogSub = null;
    _ticker?.cancel();
    state = RecState.idle;
    await Notifications.instance.cancel(Notifications.goalId);
    await Notifications.instance.cancel(Notifications.liveId);
    final t = Track([for (final s in segments) if (s.length > 1) s], laps, const [],
        [for (final s in dogSegments) if (s.isNotEmpty) [...s]]);
    notifyListeners();
    return t;
  }

  Future<void> discard() async {
    await stop();
    final id = sessionId;
    if (id != null) {
      try {
        await GpsDrafts.discard(id);
      } catch (e) {
        logError('Szkic treningu', e);
      }
    }
    sessionId = null;
    segments = [];
    meters = 0;
    dogTrack.clear();
    dogNode = null;
    notifyListeners();
  }

  void _scheduleGoal() {
    if (targetMin <= 0 || targetTimeDone) return;
    final left = targetMin * 60 - seconds;
    if (left <= 0) return;
    Notifications.instance.scheduleGoal(
      DateTime.now().add(Duration(milliseconds: (left * 1000).round())),
      tr('Cel osiągnięty! {0} min', [targetMin]),
      tr('Trening {0}: wykonaliście założony czas. Możesz kończyć albo trenować dalej.', [discipline.label]),
    );
  }

  /// Stałe powiadomienie: widać je na ekranie blokady i w pasku.
  void _updateNotification() {
    _lastNotif = seconds.floor();
    final paused = state == RecState.paused;
    final parts = <String>[
      if (useGps) tr('{0} km', [fmtKm(meters / 1000)]),
      if (useGps && meters >= 20) tr('tempo {0}/km', [_paceText(avgPace)]),
      if (targetMin > 0) targetTimeDone ? tr('cel {0} min ✓', [targetMin]) : tr('cel {0} min', [targetMin]),
    ];
    Notifications.instance.showLive(
      title: paused ? tr('Pauza – {0}', [discipline.label]) : tr('Trening trwa – {0}', [discipline.label]),
      body: parts.isEmpty ? tr('Stuknij, aby wrócić do treningu') : parts.join(' · '),
      chronoBase: paused ? null : DateTime.now().subtract(Duration(milliseconds: _watch.elapsedMilliseconds)),
    );
  }

  String _paceText(double secPerKm) {
    if (secPerKm <= 0 || secPerKm > 3600) return '–';
    final m = secPerKm ~/ 60, s = (secPerKm % 60).round();
    return s == 60 ? '${m + 1}:00' : '$m:${s.toString().padLeft(2, '0')}';
  }

  String _spoken(double sec) {
    final t = sec.round();
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
    final parts = <String>[
      if (h > 0) '$h ${h == 1 ? tr('godzina') : tr('godziny')}',
      if (m > 0) '$m ${_minWord(m)}',
      '$s ${_secWord(s)}',
    ];
    return parts.join(' ');
  }

  String _minWord(int n) => n == 1 ? tr('minuta') : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? tr('minuty') : tr('minut'));
  String _secWord(int n) => n == 1 ? tr('sekunda') : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? tr('sekundy') : tr('sekund'));

  void _say(String text) {
    _tts.speak(text).catchError((_) => null);
  }
}

/// Odcinek ruchu treningu: od [wall] (czas zegarowy) przy czasie treningu [t]
/// do [end] (pauza; null = trwa).
class _Span {
  final DateTime wall;
  final double t;
  DateTime? end;
  _Span(this.wall, this.t);
}

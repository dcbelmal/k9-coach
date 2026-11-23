import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../collar/collar_link.dart';
import '../collar/fix_filter.dart' show FixFilter;
import '../dogs/dog_profiles.dart';
import '../models.dart';
import '../storage/safe_prefs.dart';
import 'gps_drafts.dart';
import 'online_services.dart';
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

  /// Trasa psa z obroży GPS (T1000-E) i jej dystans.
  /// Segmenty trasy psa (nowy po pauzie i po utracie sygnału dłuższej niż [dogGapSec]).
  List<List<TrackPoint>> dogSegments = [];
  double dogMeters = 0;
  CollarFix? dogLast;

  /// Tracker, którego pozycje zapisujemy – ustalany na starcie i niezmienny
  /// do końca treningu (zmiana wyboru w trakcie nie przełącza źródła).
  int? dogNode;
  DateTime? _dogLastFixAt;

  /// Przerwa w pomiarach psa (s), po której zaczynamy nowy segment.
  static const dogGapSec = 90;

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

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: tr('Valkor Coach – trening {0}', [discipline.label]),
          notificationText: tr('Nagrywam trasę. Możesz wyłączyć ekran.'),
          notificationChannelName: tr('Trening GPS'),
          enableWakeLock: true,
          setOngoing: true,
          notificationIcon: AndroidResource(name: 'ic_stat_valkor', defType: 'drawable'),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
  }

  Future<void> start() async {
    // Nigdy dwa nagrania naraz: drugi start nie może wyzerować trwającej sesji.
    if (state != RecState.idle) return;
    segments = [[]];
    laps = [];
    meters = 0;
    dogSegments = [[]];
    dogMeters = 0;
    dogLast = null;
    dogNode = CollarLink.instance.dogNode;
    _dogLastFixAt = null;
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
      _dogSub?.cancel();
      _dogSub = CollarLink.instance.fixes.listen(onDogFix);
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

  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(_onPosition, onError: (e) {
      error = tr('Brak sygnału GPS');
      notifyListeners();
    });
  }

  void _onPosition(Position p) {
    if (state != RecState.running) return;
    error = null;
    final seg = segments.last;
    if (p.accuracy > (seg.isEmpty ? 40 : 25)) return; // za słaby sygnał
    final t = seconds;
    if (seg.isNotEmpty) {
      final prev = seg.last;
      final d = const Distance()(prev.ll, LatLng(p.latitude, p.longitude));
      final dt = t - prev.t;
      if (dt <= 0 && d > 10) return; // dwa odczyty w tej samej chwili daleko od siebie – błąd
      if (dt > 0 && d / dt > 16) return; // skok GPS (>57 km/h)
      if (d < 2) return;
      // Dryf w miejscu: przesunięcie mniejsze niż połowa dokładności przy niemal
      // zerowej prędkości z GPS – nie dodajemy fałszywych metrów na postoju.
      if (p.speed >= 0 && p.speed < 0.3 && d < p.accuracy * 0.5) return;
      meters += d;
      currentSpeedKmh = p.speed >= 0 ? p.speed * 3.6 : (dt > 0 ? d / dt * 3.6 : null);
    }
    seg.add(TrackPoint(p.latitude, p.longitude, t, p.speed >= 0 ? p.speed : null));
    last = p;
    _checkKm();
    notifyListeners();
  }

  /// Pozycja psa z obroży. Pauza nie zatrzymuje obroży – dopisujemy tylko
  /// w trakcie ruchu, żeby czas punktów zgadzał się z trasą człowieka.
  @visibleForTesting
  void onDogFix(CollarFix f) {
    if (state == RecState.idle) return;
    // Źródło ustalone na starcie; gdy tracker nie był jeszcze znany – pierwszy pies.
    dogNode ??= CollarLink.instance.dogNode;
    if (f.node != dogNode) return;
    dogLast = f;
    if (state != RecState.running) {
      notifyListeners();
      return;
    }
    if (dogSegments.isEmpty) dogSegments.add([]);
    // Utrata sygnału: nowy segment, bez dystansu „przez lukę”.
    final lastAt = _dogLastFixAt;
    if (lastAt != null && f.fixAt.difference(lastAt).inSeconds > dogGapSec && dogSegments.last.isNotEmpty) {
      dogSegments.add([]);
    }
    _dogLastFixAt = f.fixAt;
    if (!f.moved && dogSegments.last.isNotEmpty) {
      notifyListeners(); // postój – świeży pomiar, ale bez nowego punktu
      return;
    }
    // Czas punktu = czas pomiaru GPS przeliczony na czas ruchu treningu.
    final seg = dogSegments.last;
    var t = seconds - f.lagSec.clamp(0, 60);
    if (seg.isNotEmpty) {
      final prev = seg.last;
      if (t < prev.t) t = prev.t;
      final d = const Distance()(prev.ll, LatLng(f.lat, f.lng));
      final dt = t - prev.t;
      if (dt > 0 && d / dt > FixFilter.maxSpeedMs) return; // drugi bezpiecznik na skoki
      dogMeters += d;
    }
    seg.add(TrackPoint(f.lat, f.lng, t < 0 ? 0 : t, f.speedMs));
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
    segments.add([]);
    if (dogSegments.isEmpty || dogSegments.last.isNotEmpty) dogSegments.add([]);
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
    dogSegments = [];
    dogMeters = 0;
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

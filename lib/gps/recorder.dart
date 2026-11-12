import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../notifications.dart';
import '../theme.dart' show fmtKm;
import 'track.dart';

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
  double meters = 0;
  double? currentSpeedKmh;
  Position? last;
  String? error;
  int _announcedKm = 0;
  double _kmStartT = 0;
  double _lastLapT = 0;
  double _lastLapM = 0;
  int _waterCount = 0;

  double get seconds => _watch.elapsedMilliseconds / 1000;
  double get avgPace => meters < 20 ? 0 : seconds / meters * 1000;
  double get avgSpeedKmh => seconds <= 0 ? 0 : meters / seconds * 3.6;
  double get lapSeconds => seconds - _lastLapT;
  double get lapMeters => meters - _lastLapM;
  List<LatLng> get allPoints => [for (final s in segments) for (final p in s) p.ll];

  /// Sprawdza GPS i uprawnienia. Zwraca komunikat błędu albo null.
  static Future<String?> ensurePermission() async {
    if (kIsWeb) return 'Trening GPS działa tylko w aplikacji na telefonie.';
    if (!await Geolocator.isLocationServiceEnabled()) return 'Włącz lokalizację (GPS) w telefonie.';
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied) return 'Bez dostępu do lokalizacji nie da się nagrać trasy.';
    if (p == LocationPermission.deniedForever) {
      return 'Dostęp do lokalizacji jest zablokowany. Włącz go w ustawieniach telefonu dla K9 Coach.';
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
          notificationTitle: 'K9 Coach – trening ${discipline.label}',
          notificationText: 'Nagrywam trasę. Możesz wyłączyć ekran.',
          notificationChannelName: 'Trening GPS',
          enableWakeLock: true,
          setOngoing: true,
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
    segments = [[]];
    laps = [];
    meters = 0;
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
    _watch
      ..reset()
      ..start();
    state = RecState.running;
    try {
      await _tts.setLanguage('pl-PL');
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
    await Notifications.instance.requestPermission();
    if (useGps) _listen();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _scheduleGoal();
    _updateNotification();
    notifyListeners();
    if (voice) {
      _say('Start. Trening ${discipline.label}.${targetMin > 0 ? ' Cel: $targetMin ${_minWord(targetMin)}.' : ''}');
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(_onPosition, onError: (e) {
      error = 'Brak sygnału GPS';
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
      if (dt > 0 && d / dt > 16) return; // skok GPS (>57 km/h)
      if (d < 2) return;
      meters += d;
      currentSpeedKmh = p.speed >= 0 ? p.speed * 3.6 : (dt > 0 ? d / dt * 3.6 : null);
    }
    seg.add(TrackPoint(p.latitude, p.longitude, t, p.speed >= 0 ? p.speed : null));
    last = p;
    _checkKm();
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
        _say('Kilometr $km. Czas ${_spoken(seconds)}. Tempo ostatniego kilometra ${_spoken(kmTime)}.');
      }
    }
    if (targetKm != null && targetKm! > 0 && !targetKmDone && meters >= targetKm! * 1000) {
      targetKmDone = true;
      HapticFeedback.heavyImpact();
      _say('Cel dystansu osiągnięty. ${fmtKm(targetKm!)} kilometra. Brawo!');
    }
  }

  void _tick() {
    if (state != RecState.running) return;
    if (targetMin > 0 && !targetTimeDone && seconds >= targetMin * 60) {
      targetTimeDone = true;
      HapticFeedback.heavyImpact();
      _say('Cel osiągnięty. $targetMin ${_minWord(targetMin)} treningu. Brawo!');
    }
    if (seconds - _lastNotif >= 10) _updateNotification();
    if (waterEveryMin > 0) {
      final n = seconds ~/ (waterEveryMin * 60);
      if (n > _waterCount) {
        _waterCount = n;
        HapticFeedback.heavyImpact();
        _say('Czas na wodę dla psa.');
      }
    }
    notifyListeners();
  }

  void pause() {
    if (state != RecState.running) return;
    _watch.stop();
    state = RecState.paused;
    currentSpeedKmh = null;
    Notifications.instance.cancel(Notifications.goalId);
    _updateNotification();
    if (voice) _say('Pauza.');
    notifyListeners();
  }

  void resume() {
    if (state != RecState.paused) return;
    _watch.start();
    segments.add([]);
    state = RecState.running;
    _scheduleGoal();
    _updateNotification();
    if (voice) _say('Wznawiam.');
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
      _say('Okrążenie ${laps.length}. ${_spoken(lt)}${lm > 50 ? ', ${(lm / 1000).toStringAsFixed(2).replaceAll('.', ' przecinek ')} kilometra' : ''}.');
    }
    notifyListeners();
  }

  /// Kończy nagrywanie i zwraca trasę.
  Future<Track> stop() async {
    _watch.stop();
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    state = RecState.idle;
    await Notifications.instance.cancel(Notifications.goalId);
    await Notifications.instance.cancel(Notifications.liveId);
    final t = Track([for (final s in segments) if (s.length > 1) s], laps);
    notifyListeners();
    return t;
  }

  Future<void> discard() async {
    await stop();
    segments = [];
    meters = 0;
    notifyListeners();
  }

  void _scheduleGoal() {
    if (targetMin <= 0 || targetTimeDone) return;
    final left = targetMin * 60 - seconds;
    if (left <= 0) return;
    Notifications.instance.scheduleGoal(
      DateTime.now().add(Duration(milliseconds: (left * 1000).round())),
      'Cel osiągnięty! $targetMin min',
      'Trening ${discipline.label}: wykonaliście założony czas. Możesz kończyć albo trenować dalej.',
    );
  }

  /// Stałe powiadomienie: widać je na ekranie blokady i w pasku.
  void _updateNotification() {
    _lastNotif = seconds.floor();
    final paused = state == RecState.paused;
    final parts = <String>[
      if (useGps) '${fmtKm(meters / 1000)} km',
      if (useGps && meters >= 20) 'tempo ${_paceText(avgPace)}/km',
      if (targetMin > 0) targetTimeDone ? 'cel $targetMin min ✓' : 'cel $targetMin min',
    ];
    Notifications.instance.showLive(
      title: paused ? 'Pauza – ${discipline.label}' : 'Trening trwa – ${discipline.label}',
      body: parts.isEmpty ? 'Stuknij, aby wrócić do treningu' : parts.join(' · '),
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
      if (h > 0) '$h ${h == 1 ? 'godzina' : 'godziny'}',
      if (m > 0) '$m ${_minWord(m)}',
      '$s ${_secWord(s)}',
    ];
    return parts.join(' ');
  }

  String _minWord(int n) => n == 1 ? 'minuta' : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 'minuty' : 'minut');
  String _secWord(int n) => n == 1 ? 'sekunda' : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 'sekundy' : 'sekund');

  void _say(String text) {
    _tts.speak(text).catchError((_) => null);
  }
}

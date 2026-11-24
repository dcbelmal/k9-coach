import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models.dart' show jsonInt;
import '../notifications.dart';
import '../storage/safe_prefs.dart';
import 'collar_link.dart';

/// Bezpieczna strefa: okrąg na mapie. Wyjście psa poza nią to alarm.
class SafeZone {
  final String name;
  final double lat, lng;
  final double radiusM;
  const SafeZone(this.name, this.lat, this.lng, this.radiusM);

  LatLng get ll => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {'n': name, 'a': lat, 'o': lng, 'r': radiusM};
  static SafeZone? fromJson(dynamic j) {
    if (j is! Map) return null;
    final a = j['a'], o = j['o'], r = j['r'];
    if (a is! num || o is! num || r is! num || r <= 0) return null;
    return SafeZone('${j['n'] ?? ''}', a.toDouble(), o.toDouble(), r.toDouble());
  }
}

/// Ustawienia alarmów Valkor Track.
class AlertSettings {
  bool enabled;

  /// Wirtualna smycz (m), null = wyłączona.
  int? leashM;
  List<SafeZone> zones;

  /// Po ilu sekundach bez świeżej pozycji alarm „utracono psa”.
  int lostSec;

  /// Próg niskiej baterii trackera (%), null = wyłączony.
  int? lowBattery;
  bool voice, sound, vibrate;

  AlertSettings({
    this.enabled = false,
    this.leashM = 100,
    List<SafeZone>? zones,
    this.lostSec = 90,
    this.lowBattery = 20,
    this.voice = true,
    this.sound = true,
    this.vibrate = true,
  }) : zones = zones ?? [];

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'leash': leashM,
        'zones': [for (final z in zones) z.toJson()],
        'lost': lostSec,
        'bat': lowBattery,
        'voice': voice,
        'sound': sound,
        'vib': vibrate,
      };

  factory AlertSettings.fromJson(Map<String, dynamic> j) => AlertSettings(
        enabled: j['on'] == true,
        leashM: j.containsKey('leash') ? jsonInt(j['leash']) : 100,
        zones: [for (final z in (j['zones'] as List? ?? [])) ?SafeZone.fromJson(z)],
        lostSec: (jsonInt(j['lost']) ?? 90).clamp(30, 1800),
        lowBattery: j.containsKey('bat') ? jsonInt(j['bat']) : 20,
        voice: j['voice'] != false,
        sound: j['sound'] != false,
        vibrate: j['vib'] != false,
      );
}

enum AlertKind { leash, zone, lost, lowBattery, backInRange, found }

class DogAlert {
  final AlertKind kind;
  final String text;
  final DateTime at;
  const DogAlert(this.kind, this.text, this.at);
}

/// Co widzi silnik alarmów w danej chwili.
class AlertInput {
  final DateTime now;
  final DogLink link;
  final CollarFix? fix;

  /// Pozycja przewodnika (null = nieznana – smycz nie działa).
  final LatLng? handler;
  final int? battery;

  /// Odległość pies–przewodnik z dopasowaniem czasu i niepewnością. Gdy jest,
  /// smycz liczy się z niej (pozycja telefonu z chwili pomiaru psa).
  final DogDistance? distance;
  const AlertInput({required this.now, required this.link, this.fix, this.handler, this.battery, this.distance});
}

/// Logika alarmów – bez efektów ubocznych, łatwa do testów.
///
/// Ochrona przed fałszywymi alarmami:
/// * smycz i strefy liczone tylko z pozycji na żywo, z zapasem na błąd GPS
///   psa i telefonu; smycz porównuje pozycję psa z pozycją telefonu z tej
///   samej chwili (pozycja psa przychodzi z opóźnieniem);
/// * alarm dopiero po 2 kolejnych pomiarach poza granicą;
/// * histereza: alarm uzbraja się ponownie, gdy pies wróci wyraźnie do środka;
/// * ten sam alarm najwcześniej co [repeatSec] s.
class AlertEngine {
  AlertSettings settings;
  AlertEngine(this.settings);

  static const repeatSec = 60;
  static const confirmFixes = 2;

  final Map<AlertKind, DateTime> _lastFired = {};
  final Map<AlertKind, bool> _armed = {for (final k in AlertKind.values) k: true};
  int _leashOut = 0, _zoneOut = 0;
  DateTime? _lastFixAt;
  DateTime? _lastLiveAt;
  bool _lostActive = false;

  void reset() {
    _lastFired.clear();
    for (final k in AlertKind.values) {
      _armed[k] = true;
    }
    _leashOut = _zoneOut = 0;
    _lastFixAt = _lastLiveAt = null;
    _lostActive = false;
  }

  List<DogAlert> evaluate(AlertInput i) {
    final out = <DogAlert>[];
    if (!settings.enabled) return out;
    void fire(AlertKind k, String text) {
      final last = _lastFired[k];
      if (last != null && i.now.difference(last).inSeconds < repeatSec) return;
      _lastFired[k] = i.now;
      out.add(DogAlert(k, text, i.now));
    }

    final live = i.link == DogLink.live;
    if (live) _lastLiveAt = i.now;

    // Utrata psa: brak świeżej pozycji przez lostSec (od ostatniej pozycji na żywo).
    final since = _lastLiveAt;
    if (!live && since != null && i.now.difference(since).inSeconds >= settings.lostSec) {
      if (!_lostActive) {
        _lostActive = true;
        fire(AlertKind.lost, _lostText(i.link));
      }
    } else if (live && _lostActive) {
      _lostActive = false;
      fire(AlertKind.found, tr('Znów widzę psa.'));
    }

    // Smycz i strefy: tylko nowy pomiar na żywo.
    final f = i.fix;
    final newFix = f != null && f.fixAt != _lastFixAt;
    if (live && newFix) {
      _lastFixAt = f.fixAt;
      final acc = (f.accuracyM ?? 10).clamp(5, 50).toDouble();

      final leash = settings.leashM;
      final h = i.handler;
      final dd = i.distance;
      final matched = dd?.matchedM != null;
      if (leash != null && leash > 0 && (matched || h != null)) {
        final d = matched ? dd!.matchedM! : const Distance()(h!, f.ll);
        final margin = matched ? dd!.matchedUncertaintyM! : acc;
        if (d > leash + margin) {
          _leashOut++;
          if (_leashOut >= confirmFixes && _armed[AlertKind.leash]!) {
            _armed[AlertKind.leash] = false;
            fire(AlertKind.leash, tr('Pies jest {0} metrów od Ciebie.', [d.round()]));
          }
        } else {
          _leashOut = 0;
          if (d < leash * 0.8 && !_armed[AlertKind.leash]!) {
            _armed[AlertKind.leash] = true;
            fire(AlertKind.backInRange, tr('Pies wrócił bliżej.'));
          }
        }
      }

      if (settings.zones.isNotEmpty) {
        final inside = settings.zones.any((z) => const Distance()(z.ll, f.ll) <= z.radiusM + acc);
        final deepInside = settings.zones.any((z) => const Distance()(z.ll, f.ll) <= z.radiusM * 0.9);
        if (!inside) {
          _zoneOut++;
          if (_zoneOut >= confirmFixes && _armed[AlertKind.zone]!) {
            _armed[AlertKind.zone] = false;
            fire(AlertKind.zone, tr('Pies wyszedł poza bezpieczną strefę.'));
          }
        } else {
          _zoneOut = 0;
          if (deepInside) _armed[AlertKind.zone] = true;
        }
      }
    }

    // Niska bateria trackera (raz, ponownie dopiero po naładowaniu o 5 punktów).
    final low = settings.lowBattery, b = i.battery;
    if (low != null && b != null && b <= 100) {
      if (b <= low && _armed[AlertKind.lowBattery]!) {
        _armed[AlertKind.lowBattery] = false;
        fire(AlertKind.lowBattery, tr('Słaba bateria trackera: {0} procent.', [b]));
      } else if (b > low + 5) {
        _armed[AlertKind.lowBattery] = true;
      }
    }
    return out;
  }

  String _lostText(DogLink l) => switch (l) {
        DogLink.bluetoothOff || DogLink.connecting => tr('Utracono połączenie Bluetooth z trackerem.'),
        DogLink.loraSilent => tr('Brak sygnału radiowego od psa.'),
        _ => tr('Brak świeżej pozycji psa.'),
      };
}

/// Alarmy Valkor Track w aplikacji: głos, dźwięk, wibracja i powiadomienie.
///
/// Działa, dopóki działa aplikacja – w trakcie treningu GPS także przy
/// wygaszonym ekranie (usługa nagrywania trzyma aplikację przy życiu).
class DogAlerts extends ChangeNotifier {
  DogAlerts._();
  static final DogAlerts instance = DogAlerts._();
  static const _key = 'valkor_alerts_v1';
  static const notifId = 75420;

  final engine = AlertEngine(AlertSettings());
  AlertSettings get settings => engine.settings;

  /// Pozycja przewodnika (ustawiana przez trening albo ekran Valkor Track).
  LatLng? handler;
  DateTime? handlerAt;

  final List<DogAlert> history = [];
  Timer? _timer;
  FlutterTts? _tts;
  bool _loaded = false;

  /// Wyjście alarmu (podmieniane w testach).
  @visibleForTesting
  void Function(DogAlert a)? onAlert;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) engine.settings = AlertSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      logError('Alarmy Valkor Track', e);
    }
    _sync();
    notifyListeners();
  }

  Future<void> save(AlertSettings s) async {
    engine.settings = s;
    engine.reset();
    _sync();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await SafePrefs.setString(p, _key, jsonEncode(s.toJson()));
    } catch (e) {
      logError('Alarmy Valkor Track', e);
    }
  }

  /// Pozycja przewodnika; trafia też do historii pozycji telefonu
  /// ([HandlerTrack]), z której liczymy odległość w chwili pomiaru psa.
  void setHandler(LatLng? p, {double? accuracyM, DateTime? at}) {
    final now = DateTime.now();
    handler = p;
    handlerAt = p == null ? null : now;
    if (p != null) {
      // Czas pomiaru z GPS telefonu, chyba że wyraźnie odbiega od zegara.
      final t = at != null && now.difference(at).inSeconds.abs() <= 30 ? at.toLocal() : now;
      HandlerTrack.instance.add(HandlerFix(t, p.latitude, p.longitude, accuracyM: accuracyM != null && accuracyM > 0 ? accuracyM : null));
    }
  }

  /// Włączone alarmy sprawdzamy co 2 s.
  void _sync() {
    if (settings.enabled && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    } else if (!settings.enabled) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void check({DateTime? now}) {
    final c = CollarLink.instance;
    if (!c.paired) return;
    final t = now ?? DateTime.now();
    // Pozycja przewodnika starsza niż 2 min nie służy do smyczy.
    final h = handlerAt != null && t.difference(handlerAt!).inSeconds <= 120 ? handler : null;
    final out = engine.evaluate(AlertInput(
      now: t,
      link: c.status(now: t),
      fix: c.dog?.fix,
      handler: h,
      battery: c.dog?.battery,
      distance: DogDistance.of(c.dog?.fix, HandlerTrack.instance, now: t),
    ));
    for (final a in out) {
      _emit(a);
    }
  }

  void _emit(DogAlert a) {
    history.insert(0, a);
    if (history.length > 30) history.removeLast();
    notifyListeners();
    final hook = onAlert;
    if (hook != null) {
      hook(a);
      return;
    }
    final s = settings;
    final calm = a.kind == AlertKind.backInRange || a.kind == AlertKind.found;
    try {
      if (s.vibrate) HapticFeedback.heavyImpact();
      if (s.sound && !calm) SystemSound.play(SystemSoundType.alert);
      if (s.voice) {
        _tts ??= FlutterTts();
        _tts!.speak(a.text);
      }
      if (!calm) Notifications.instance.showNow(notifId, tr('Valkor Track'), a.text);
    } catch (e) {
      logError('Alarmy Valkor Track', e);
    }
  }

  @visibleForTesting
  void resetForTest() {
    engine.settings = AlertSettings();
    engine.reset();
    history.clear();
    handler = null;
    handlerAt = null;
    HandlerTrack.instance.clear();
    _timer?.cancel();
    _timer = null;
    _loaded = true;
  }
}

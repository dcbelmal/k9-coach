import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'collar_link.dart';

/// Etap eksperymentu z szybszym raportowaniem pozycji.
enum FastPhase {
  idle,

  /// Zapis ustawień w trackerze i potwierdzenie odczytem.
  applying,

  /// Pomiar rzeczywistego odstępu po zmianie.
  measuring,

  /// Pomiar zakończony – wynik w [FastModeExperiment.result].
  done,

  /// Przywracanie stabilnych ustawień 5 s.
  restoring,

  /// Błąd (ustawień nie dało się zapisać albo przywrócić).
  failed,
}

/// Eksperymentalny tryb szybkiego śledzenia (tylko w diagnostyce).
///
/// Porównuje rzeczywisty odstęp nowych pozycji przy ustawieniach 5 s
/// (odniesienie = profil sportowy, bez zmian), 2 s i 1 s (test). Nie zmienia
/// firmware i nie tworzy pozycji – mierzy tylko to, co tracker naprawdę
/// przysłał. Osobno pokazuje:
/// * GNSS – co ile tracker mierzy pozycję (interwał GPS w ustawieniach);
/// * LoRa – co ile wolno nadać pozycję (interwał rozgłaszania, limit radia);
/// * Bluetooth – co ile telefon odebrał pakiet (zmierzone);
/// * nowe pomiary – odstęp czasów pomiaru GPS w pakietach (zmierzone);
/// * ekran – odświeżanie widoku co 1 s (bez dorysowywania pozycji).
///
/// Gdy firmware nie raportuje szybciej (mediana ponad 1,5 × cel), aplikacja
/// sama przywraca stabilne ustawienia 5 s i opisuje ograniczenie.
class FastModeExperiment extends ChangeNotifier {
  FastModeExperiment(this.link);
  final CollarLink link;

  /// Ustawienia testowe: rozgłaszanie co [sec] s, GPS co 1 s, preset
  /// SHORT_FAST (najkrótszy czas nadawania). 5 s = profil sportowy.
  static const exp2 = TrackerProfile('exp2', 2, 1, preset: 6);
  static const exp1 = TrackerProfile('exp1', 1, 1, preset: 6);
  static TrackerProfile profileFor(int sec) => switch (sec) { 1 => exp1, 2 => exp2, _ => TrackerProfile.sport };

  /// Ile odstępów mierzymy i najdłużej ile czekamy.
  static const wantIntervals = 12;
  static const measureMaxSec = 120;

  /// Firmware Meshtastic sprawdza, czy wysłać pozycję, co 5 s
  /// (PositionModule::runOnce) – to ograniczenie, którego ustawienia nie zmienią.
  static const firmwareCheckSec = 5;

  /// Zegar (podmieniany w testach).
  static DateTime Function() clock = DateTime.now;

  FastPhase phase = FastPhase.idle;
  int? targetSec;
  DateTime? measureFrom;
  final List<double> fixIntervals = [];
  final List<double> rxIntervals = [];
  DateTime? _lastFixAt, _lastRxAt;
  double? resultMedianSec, resultRxMedianSec;
  String? message;
  bool limitedByFirmware = false;
  Timer? _timer;
  bool _listening = false;

  /// Historia wyników (cel → zmierzona mediana) do raportu.
  final List<(int, double?, double?)> results = [];

  /// Najkrótszy odstęp, na jaki pozwala radio po zmianie na profil [p].
  double radioMinAfter(TrackerProfile p) {
    final c = link.config;
    final after = TrackerConfig()
      ..device = c.device
      ..position = p.positionBytes(c)
      ..lora = p.loraBytes(c) ?? c.lora;
    return after.radioMinSec;
  }

  /// Dlaczego nie można teraz uruchomić testu [sec] (null = można).
  String? blocker(int sec) {
    if (phase == FastPhase.applying || phase == FastPhase.measuring || phase == FastPhase.restoring) {
      return tr('Trwa poprzedni test.');
    }
    if (!link.connected || !link.config.known) return tr('Najpierw połącz tracker i poczekaj na odczyt jego ustawień.');
    if (!link.direct) return tr('Test działa tylko przy bezpośrednim połączeniu z trackerem na psie.');
    final r = radioMinAfter(profileFor(sec));
    if (r > sec) {
      return tr('Limit radia: przy tych ustawieniach pozycja może iść najczęściej co ~{0} s – test {1} s przeciążyłby radio.',
          [r.toStringAsFixed(1).replaceAll('.', ','), sec]);
    }
    return null;
  }

  /// Uruchamia test z celem [sec] s (5 = odniesienie). Zwraca błąd albo null.
  Future<String?> start(int sec) async {
    final b = blocker(sec);
    if (b != null) return b;
    _cancel();
    targetSec = sec;
    resultMedianSec = resultRxMedianSec = null;
    limitedByFirmware = false;
    message = null;
    _clearSamples();
    final p = profileFor(sec);
    if (p.matches(link.config)) {
      // Ustawienia już są – od razu mierzymy.
      _startMeasuring();
      return null;
    }
    phase = FastPhase.applying;
    _listen();
    notifyListeners();
    final err = await link.applyProfile(p);
    if (err != null) {
      phase = FastPhase.failed;
      message = err;
      _unlisten();
      notifyListeners();
    }
    return err;
  }

  /// Ręczny powrót do stabilnych ustawień 5 s.
  Future<String?> restore([String? why]) async {
    _cancel();
    if (link.config.known && TrackerProfile.sport.matches(link.config)) {
      phase = FastPhase.done;
      if (why != null) message = why;
      notifyListeners();
      return null;
    }
    phase = FastPhase.restoring;
    if (why != null) message = why;
    _listen();
    notifyListeners();
    final err = await link.applyProfile(TrackerProfile.sport);
    if (err != null) {
      phase = FastPhase.failed;
      message = tr('Nie udało się przywrócić ustawień 5 s: {0}', [err]);
      _unlisten();
      notifyListeners();
    }
    return err;
  }

  /// Ustawienia trackera to teraz ustawienia testowe (nie 5 s).
  bool get testSettingsActive =>
      link.config.known && (exp1.matches(link.config) || exp2.matches(link.config));

  /// Nowy pomiar psa na żywo (czas pomiaru [f.fixAt], odebrany o [rx]).
  void onLiveFix(CollarFix f, DateTime rx) {
    if (phase != FastPhase.measuring) return;
    final from = measureFrom;
    if (from == null || rx.isBefore(from)) return;
    final pr = _lastRxAt;
    _lastRxAt = rx;
    if (pr != null) {
      final s = rx.difference(pr).inMilliseconds / 1000;
      if (s > 0 && s < 600) rxIntervals.add(s);
    }
    if (f.timeIsFix) {
      final pf = _lastFixAt;
      _lastFixAt = f.fixAt;
      if (pf != null) {
        final s = f.fixAt.difference(pf).inMilliseconds / 1000;
        if (s > 0 && s < 600) fixIntervals.add(s);
      }
    }
    if (fixIntervals.length >= wantIntervals) _finish();
    notifyListeners();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    link.addListener(_onLink);
  }

  void _unlisten() {
    if (!_listening) return;
    _listening = false;
    link.removeListener(_onLink);
  }

  void _onLink() {
    if (phase == FastPhase.applying) {
      if (link.applyState == ProfileApply.verified) {
        _unlisten();
        _startMeasuring();
      } else if (link.applyState == ProfileApply.failed) {
        _unlisten();
        final e = link.applyError;
        // Część ustawień mogła się zapisać – wracamy do stabilnych 5 s.
        restore(tr('Tracker nie przyjął ustawień testowych ({0}). Przywracam 5 s.', [e ?? '']));
      }
    } else if (phase == FastPhase.restoring) {
      if (link.applyState == ProfileApply.verified) {
        _unlisten();
        phase = FastPhase.done;
        notifyListeners();
      } else if (link.applyState == ProfileApply.failed) {
        _unlisten();
        phase = FastPhase.failed;
        message = tr('Nie udało się przywrócić ustawień 5 s: {0}', [link.applyError ?? '']);
        notifyListeners();
      }
    }
  }

  void _startMeasuring() {
    phase = FastPhase.measuring;
    measureFrom = clock();
    _clearSamples();
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: measureMaxSec), _finish);
    notifyListeners();
  }

  @visibleForTesting
  void finishNow() => _finish();

  void _finish() {
    if (phase != FastPhase.measuring) return;
    _timer?.cancel();
    _timer = null;
    final t = targetSec ?? 5;
    final m = median(fixIntervals) ?? median(rxIntervals);
    resultMedianSec = m;
    resultRxMedianSec = median(rxIntervals);
    results.add((t, m, resultRxMedianSec));
    phase = FastPhase.done;
    if (m == null) {
      message = tr('Za mało pozycji w czasie testu ({0}) – nie da się ocenić odstępu.', [fixIntervals.length]);
      if (t < 5) {
        restore(message);
        return;
      }
    } else if (t < 5 && m > t * 1.5) {
      limitedByFirmware = m >= firmwareCheckSec * 0.8;
      message = limitedByFirmware
          ? tr('Tracker nadal raportuje co ~{0} s mimo ustawienia {1} s. Firmware Meshtastic sprawdza pozycję co 5 s, więc szybciej się nie da bez zmiany firmware. Przywracam stabilne ustawienia 5 s.',
              [_fmt(m), t])
          : tr('Odstęp ~{0} s zamiast {1} s – cel nieosiągnięty. Przywracam stabilne ustawienia 5 s.', [_fmt(m), t]);
      restore(message);
      return;
    } else {
      message = tr('Zmierzony odstęp nowych pozycji: ~{0} s (cel {1} s).', [_fmt(m), t]);
    }
    notifyListeners();
  }

  static double? median(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  static String _fmt(double s) => s.toStringAsFixed(1).replaceAll('.', ',');

  /// Częstotliwości poszczególnych warstw: (nazwa, wartość).
  List<(String, String)> rates() {
    final c = link.config;
    final rx = median(rxIntervals) ?? (link.diag.rxIntervals.isEmpty ? null : median(link.diag.rxIntervals));
    final fx = median(fixIntervals) ?? link.diag.medianInterval;
    return [
      (tr('GNSS (pomiar w trackerze)'), c.known ? tr('co {0} s', [c.effectiveGpsUpdateSecs]) : '–'),
      (tr('LoRa (rozgłaszanie)'), c.known ? tr('co {0} s', [c.effectiveBroadcastSecs]) : '–'),
      (tr('Limit radia'), c.known ? tr('najczęściej co ~{0} s', [_fmt(c.radioMinSec)]) : '–'),
      (tr('Firmware (sprawdzanie pozycji)'), tr('co {0} s', [firmwareCheckSec])),
      (tr('Odbiór przez Bluetooth'), rx == null ? '–' : tr('co ~{0} s', [_fmt(rx)])),
      (tr('Nowe pomiary (czas GPS)'), fx == null ? '–' : tr('co ~{0} s', [_fmt(fx)])),
      (tr('Odświeżanie ekranu'), tr('co 1 s (bez dorysowywania pozycji)')),
    ];
  }

  List<String> csvLines() => [
        'tryb_szybki;etap;${phase.name}',
        'tryb_szybki;cel_s;${targetSec ?? ''}',
        'tryb_szybki;ustawienia_testowe_aktywne;${testSettingsActive ? 1 : 0}',
        for (final r in results)
          'tryb_szybki;wynik_cel_${r.$1}_s;mediana_pomiarow=${r.$2?.toStringAsFixed(2) ?? ''};mediana_odbioru=${r.$3?.toStringAsFixed(2) ?? ''}',
        'tryb_szybki;komunikat;${(message ?? '').replaceAll(';', ',')}',
      ];

  void _clearSamples() {
    fixIntervals.clear();
    rxIntervals.clear();
    _lastFixAt = _lastRxAt = null;
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _unlisten();
  }

  /// Zapomina wyniki i przerywa test (bez zmiany ustawień trackera).
  void reset() {
    _cancel();
    phase = FastPhase.idle;
    targetSec = null;
    measureFrom = null;
    resultMedianSec = resultRxMedianSec = null;
    message = null;
    limitedByFirmware = false;
    results.clear();
    _clearSamples();
  }

  /// Najkrótszy sensowny cel przy obecnym presecie (do opisu w raporcie).
  double get bestPossibleSec => math.max(firmwareCheckSec.toDouble(), link.config.radioMinSec);
}

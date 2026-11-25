// Stan aplikacji (pierwszy plan / tło) – do dziennika pomiarów i testów pracy w tle.
import 'package:flutter/widgets.dart';

import '../app_version.dart';

/// Identyfikator kompilacji: numer kompilacji z pubspec (build), commit
/// (--dart-define=VALKOR_COMMIT w GitHub Actions; „local” przy kompilacji ręcznej).
const appBuildNumber = int.fromEnvironment('VALKOR_BUILD', defaultValue: 42);
const appCommit = String.fromEnvironment('VALKOR_COMMIT', defaultValue: 'local');
String get appBuildId => '$appVersion+$appBuildNumber ($appCommit)';

class AppState with WidgetsBindingObserver {
  AppState._();
  static final AppState instance = AppState._();

  AppLifecycleState? _state;
  bool _observing = false;

  /// Przejścia do tła i z powrotem (od uruchomienia aplikacji).
  int toBackground = 0, toForeground = 0;
  DateTime? backgroundSince;

  /// Łączny czas w tle (s), łącznie z bieżącym pobytem.
  double backgroundSec([DateTime? now]) {
    final b = backgroundSince;
    return _bgSec + (b == null ? 0 : (now ?? DateTime.now()).difference(b).inMilliseconds / 1000);
  }

  double _bgSec = 0;

  void observe() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {}
  }

  bool get background => _state != null && _state != AppLifecycleState.resumed;

  /// Do CSV: „pierwszy_plan” albo „tlo”.
  String get csv => background ? 'tlo' : 'pierwszy_plan';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => note(state);

  @visibleForTesting
  void note(AppLifecycleState state, {DateTime? at}) {
    final t = at ?? DateTime.now();
    final wasBg = background;
    _state = state;
    if (!wasBg && background) {
      toBackground++;
      backgroundSince = t;
    } else if (wasBg && !background) {
      toForeground++;
      final b = backgroundSince;
      if (b != null) _bgSec += t.difference(b).inMilliseconds / 1000;
      backgroundSince = null;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _state = null;
    toBackground = toForeground = 0;
    backgroundSince = null;
    _bgSec = 0;
  }
}

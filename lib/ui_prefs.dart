import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'storage/safe_prefs.dart';

/// Ostatnie ustawienia szybkiego startu treningu jednego psa.
class QuickStart {
  final Discipline discipline;
  final int targetMin;
  final double? targetKm;
  const QuickStart(this.discipline, {this.targetMin = 0, this.targetKm});

  Map<String, dynamic> toJson() => {'d': discipline.name, 'min': targetMin, if (targetKm != null) 'km': targetKm};

  static QuickStart? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = Discipline.values.where((e) => e.name == j['d']).firstOrNull;
    if (d == null) return null;
    return QuickStart(d,
        targetMin: (j['min'] as num?)?.toInt() ?? 0, targetKm: (j['km'] as num?)?.toDouble());
  }
}

/// Karty ekranu Start, które użytkownik może ukryć (dane zostają nietknięte).
enum HomeCard {
  reminders('Najbliższe przypomnienia'),
  lastActivity('Ostatnia aktywność'),
  stats('Statystyki tygodnia'),
  care('Żywienie i zdrowie'),
  events('Nadchodzące wydarzenia'),
  shortcuts('Skróty');

  final String plLabel;
  const HomeCard(this.plLabel);
}

/// Ustawienia wyglądu i wygody obsługi. Osobny klucz, poza danymi psów:
/// uszkodzenie lub brak tego zapisu nie wpływa na treningi ani profile.
///
/// * szybki start: osobno dla każdego psa (po jego identyfikatorze),
/// * ukryte karty Start: wspólne dla całej aplikacji.
class UiPrefs extends ChangeNotifier {
  UiPrefs._();
  static final UiPrefs instance = UiPrefs._();
  static const _key = 'valkor_ui_v1';

  final Map<String, QuickStart> _quick = {};
  final Set<HomeCard> hidden = {};

  QuickStart? quickFor(String dogId) => _quick[dogId];
  bool shows(HomeCard c) => !hidden.contains(c);

  Future<void> load() async {
    _quick.clear();
    hidden.clear();
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final q = j['quick'];
        if (q is Map) {
          for (final e in q.entries) {
            final v = QuickStart.fromJson(e.value);
            if (v != null) _quick['${e.key}'] = v;
          }
        }
        final h = j['hidden'];
        if (h is List) {
          hidden.addAll(HomeCard.values.where((c) => h.contains(c.name)));
        }
      }
    } catch (e) {
      // Nieczytelne ustawienia wyglądu = ustawienia domyślne. Dane psów są gdzie indziej.
      logError('Ustawienia wyglądu', e);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await SafePrefs.setString(
        p,
        _key,
        jsonEncode({
          'quick': {for (final e in _quick.entries) e.key: e.value.toJson()},
          'hidden': [for (final c in hidden) c.name],
        }));
  }

  /// Zapamiętanie ustawień po rozpoczęciu treningu. Błąd zapisu nie przerywa
  /// treningu: to tylko wygoda, więc go zgłaszamy do logu i idziemy dalej.
  Future<void> rememberStart(String dogId, QuickStart q) async {
    _quick[dogId] = q;
    notifyListeners();
    try {
      await _save();
    } catch (e) {
      logError('Szybki start', e);
    }
  }

  Future<void> forgetDog(String dogId) async {
    if (_quick.remove(dogId) == null) return;
    try {
      await _save();
    } catch (e) {
      logError('Szybki start', e);
    }
  }

  /// Pokaż albo ukryj kartę. Przy błędzie zapisu stan wraca i błąd idzie wyżej.
  Future<void> setShown(HomeCard c, bool show) async {
    final was = shows(c);
    if (show) {
      hidden.remove(c);
    } else {
      hidden.add(c);
    }
    notifyListeners();
    try {
      await _save();
    } catch (e) {
      if (was) {
        hidden.remove(c);
      } else {
        hidden.add(c);
      }
      notifyListeners();
      rethrow;
    }
  }
}

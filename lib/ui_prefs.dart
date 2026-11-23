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

  /// Kiedy zapamiętano ustawienia (null = zapis sprzed wersji 0.13.1).
  final DateTime? at;
  const QuickStart(this.discipline, {this.targetMin = 0, this.targetKm, this.at});

  Map<String, dynamic> toJson() => {
        'd': discipline.name,
        'min': targetMin,
        if (targetKm != null) 'km': targetKm,
        if (at != null) 'at': at!.millisecondsSinceEpoch,
      };

  /// Odczyt odporny na uszkodzony zapis: zły typ albo wartość spoza zakresu
  /// daje wartość domyślną zamiast wyjątku. Nieznana dyscyplina = brak ustawień.
  static QuickStart? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = Discipline.values.where((e) => e.name == j['d']).firstOrNull;
    if (d == null) return null;
    final min = j['min'];
    final km = j['km'];
    final at = j['at'];
    final kmVal = km is num && km.isFinite && km > 0 && km <= 500 ? km.toDouble() : null;
    return QuickStart(d,
        targetMin: min is num && min.isFinite && min > 0 && min <= 24 * 60 ? min.toInt() : 0,
        targetKm: d.hasDistance ? kmVal : null,
        at: at is int && at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : null);
  }
}

/// Karty ekranu Start, które użytkownik może ukryć (dane zostają nietknięte).
enum HomeCard {
  reminders('Najbliższe przypomnienia'),
  track('Valkor Track'),
  performance('Valkor Performance'),
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
        final j = jsonDecode(raw);
        if (j is! Map) throw const FormatException('valkor_ui_v1: oczekiwano obiektu');
        final q = j['quick'];
        if (q is Map) {
          for (final e in q.entries) {
            // Jeden uszkodzony wpis nie kasuje ustawień pozostałych psów.
            try {
              final v = QuickStart.fromJson(e.value);
              if (v != null) _quick['${e.key}'] = v;
            } catch (_) {}
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

  /// Zapisy po kolei: każdy zapisuje aktualny stan w chwili wykonania, więc
  /// przy szybkich zmianach (np. przełączanie psów) ostatni zapis jest zawsze
  /// najnowszy i żaden starszy go nie nadpisze.
  final _queue = SerialQueue();

  Future<void> _save() => _queue.run(() async {
        final p = await SharedPreferences.getInstance();
        await SafePrefs.setString(
            p,
            _key,
            jsonEncode({
              'quick': {for (final e in _quick.entries) e.key: e.value.toJson()},
              'hidden': [for (final c in hidden) c.name],
            }));
      });

  /// Zapamiętanie ustawień po rozpoczęciu treningu. Błąd zapisu nie przerywa
  /// treningu: to tylko wygoda, więc go zgłaszamy do logu i idziemy dalej.
  Future<void> rememberStart(String dogId, QuickStart q) async {
    _quick[dogId] = QuickStart(q.discipline,
        targetMin: q.targetMin, targetKm: q.discipline.hasDistance ? q.targetKm : null, at: q.at ?? DateTime.now());
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
      // Cofamy tylko, jeśli w międzyczasie nikt nie zmienił tej karty ponownie.
      if (shows(c) == show) {
        if (was) {
          hidden.remove(c);
        } else {
          hidden.add(c);
        }
        notifyListeners();
      }
      rethrow;
    }
  }
}

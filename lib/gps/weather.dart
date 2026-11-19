import 'dart:convert';

import 'package:http/http.dart' as http;
import '../breeds/breed_profile.dart';
import '../models.dart';
import '../nutrition/energy.dart';
import '../theme.dart';
import '../l10n/l10n.dart';

/// Cechy psa zwiększające ryzyko przegrzania (Hall i wsp. 2020, VetCompass:
/// rasy krótkoczaszkowe, nadwaga, wiek, gęsta szata; Bruchim 2017).
class HeatDogFactors {
  final List<String> reasons;
  const HeatDogFactors(this.reasons);
  static const none = HeatDogFactors([]);

  factory HeatDogFactors.of(Dog? d, [DateTime? now]) {
    if (d == null) return none;
    final p = breedProfileFor(d.breedId);
    final months = Energy.ageMonths(d.birthDate, now);
    final adult = Energy.expectedAdultKg(d);
    return HeatDogFactors([
      if (p != null && (p.has(BreedTrait.brachy) || p.has(BreedTrait.brachyMild))) tr('krótka kufa'),
      if (p != null && p.has(BreedTrait.heatSensitive)) tr('gęsta szata lub budowa utrudniająca chłodzenie'),
      if ((d.bcs ?? 0) >= 7) tr('nadwaga'),
      if (Energy.isSenior(months, adultKg: adult)) tr('wiek senioralny'),
      if (months != null && months < 12) tr('młody pies'),
      if (p != null && p.has(BreedTrait.cardiac)) tr('predyspozycja do chorób serca'),
    ]);
  }
}

/// Ocena ryzyka cieplnego przed treningiem.
class HeatAssessment {
  final int level; // 0 = niskie, 1 = podwyższone, 2 = wysokie
  final List<String> reasons;
  final String advice;
  const HeatAssessment(this.level, this.reasons, this.advice);
}

class Weather {
  final double temp;
  final double feels;
  final int humidity;
  final double? radiation; // promieniowanie krótkofalowe W/m² (nasłonecznienie)
  final bool? isDay;
  final double? windKmh;
  const Weather(this.temp, this.feels, this.humidity, {this.radiation, this.isDay, this.windKmh});

  bool get strongSun => (isDay ?? true) && (radiation ?? 0) >= 600;

  /// Ocena ryzyka przegrzania psa.
  ///
  /// Nie istnieje zwalidowany „indeks ciepła” dla psów – temperatura odczuwalna
  /// jest liczona dla ludzi (pocenie), a pies oddaje ciepło głównie dysząc, więc
  /// wysoka wilgotność szkodzi mu bardziej. Progi poniżej są ostrożnymi progami
  /// aplikacji opartymi na danych o udarach cieplnych u psów (Hall i wsp. 2020:
  /// większość przypadków po wysiłku, także przy umiarkowanych temperaturach),
  /// a nie granicą bezpieczeństwa.
  HeatAssessment assess({bool highIntensity = true, int? plannedMin, HeatDogFactors dog = HeatDogFactors.none}) {
    final reasons = <String>[];
    final t = temp > feels ? temp : feels;
    // Bazowe pasma dla wysiłku o dużej intensywności (bieg, ciągnięcie).
    var points = t >= 20 ? 3 : (t >= 15 ? 2 : (t >= 10 ? 1 : 0));
    if (t >= 15) reasons.add(tr('{0}°C', [fmtNum(t)]));
    if (humidity >= 70 && temp >= 12) {
      points++;
      reasons.add(tr('wilgotność {0}% utrudnia chłodzenie dyszeniem', [humidity]));
    }
    if (strongSun && temp >= 12) {
      points++;
      reasons.add(tr('silne nasłonecznienie'));
    }
    if ((plannedMin ?? 0) > 30 && temp >= 10) {
      points++;
      reasons.add(tr('długi trening ({0} min)', [plannedMin]));
    }
    if (dog.reasons.isNotEmpty && temp >= 10) {
      points++;
      reasons.addAll(dog.reasons);
    }
    if (!highIntensity) points -= 2;
    final level = points >= 4 ? 2 : (points >= 2 ? 1 : 0);
    final advice = switch (level) {
      2 => highIntensity
          ? tr('Wysokie ryzyko przegrzania przy biegu. Wybierz spokojny spacer w cieniu, trening przy wodzie albo wczesny poranek. Przerwij od razu, gdy pies mocno dyszy, zwalnia lub się zatacza.')
          : tr('Ciepło – krótki, spokojny spacer w cieniu, woda, bez zabaw w biegu.'),
      1 => tr('Podwyższone ryzyko. Skróć trening, zwolnij, rób przerwy w cieniu i podawaj wodę. Obserwuj język, oddech i tempo psa.'),
      _ => tr('Warunki zwykle dobre, ale obserwuj psa – przegrzanie zdarza się także w chłodniejsze dni przy dużym wysiłku.'),
    };
    return HeatAssessment(level, reasons, advice);
  }

  /// Ryzyko dla biegu z psem bez dodatkowych danych (zgodność wstecz).
  int get risk => assess().level;

  String get advice => assess().advice;
}

/// Aktualna pogoda z Open-Meteo (bez klucza i konta).
Future<Weather?> fetchWeather(double lat, double lng) async {
  try {
    final r = await http
        .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(3)}'
            '&longitude=${lng.toStringAsFixed(3)}&current=temperature_2m,apparent_temperature,relative_humidity_2m,'
            'shortwave_radiation,is_day,wind_speed_10m'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    return parseWeather(jsonDecode(r.body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Weather? parseWeather(Map<String, dynamic> j) {
  final c = j['current'];
  if (c is! Map<String, dynamic>) return null;
  final t = c['temperature_2m'], f = c['apparent_temperature'], h = c['relative_humidity_2m'];
  if (t is! num || f is! num || h is! num) return null;
  return Weather(t.toDouble(), f.toDouble(), h.round(),
      radiation: (c['shortwave_radiation'] as num?)?.toDouble(),
      isDay: c['is_day'] == null ? null : c['is_day'] == 1,
      windKmh: (c['wind_speed_10m'] as num?)?.toDouble());
}

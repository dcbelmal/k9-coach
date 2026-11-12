import 'dart:convert';

import 'package:http/http.dart' as http;

class Weather {
  final double temp;
  final double feels;
  final int humidity;
  const Weather(this.temp, this.feels, this.humidity);

  /// 0 = ok, 1 = uwaga, 2 = za gorąco na bieg z psem.
  int get risk => feels >= 22 || temp >= 20 ? 2 : (feels >= 15 || temp >= 15 ? 1 : 0);

  String get advice => switch (risk) {
        2 => 'Za gorąco na canicross i bikejoring. Wybierz spokojny spacer, wodę lub trening wcześnie rano.',
        1 => 'Ciepło. Skróć dystans, biegnij wolniej, zabierz wodę i obserwuj język i oddech psa.',
        _ => 'Dobre warunki do biegu z psem.',
      };
}

/// Aktualna pogoda z Open-Meteo (bez klucza i konta).
Future<Weather?> fetchWeather(double lat, double lng) async {
  try {
    final r = await http
        .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(3)}'
            '&longitude=${lng.toStringAsFixed(3)}&current=temperature_2m,apparent_temperature,relative_humidity_2m'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final c = (jsonDecode(r.body) as Map<String, dynamic>)['current'] as Map<String, dynamic>;
    return Weather((c['temperature_2m'] as num).toDouble(), (c['apparent_temperature'] as num).toDouble(),
        (c['relative_humidity_2m'] as num).round());
  } catch (_) {
    return null;
  }
}

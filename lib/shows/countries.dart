import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

/// Kraj członkowski FCI (lub sąsiad) – kod ISO, nazwa i flaga.
class ShowCountry {
  final String code;
  final String name;
  /// false = związek kynologiczny kraju nie publikuje dziś wystaw w kalendarzu FCI (np. Rosja – zawieszona w FCI).
  final bool inFci;
  const ShowCountry(this.code, this.name, {this.inFci = true});

  /// Flaga z kodu ISO (dwie litery → dwa symbole regionalne).
  String get flag => String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  /// Nazwa w języku aplikacji (klucz tłumaczenia = nazwa polska).
  String get localName => tr(name);

  String get label => '$flag $localName';
}

/// Kraje Europy, dla których FCI publikuje kalendarz wystaw.
/// Nazwy w jednym miejscu, żeby łatwo je przetłumaczyć.
const showCountries = <ShowCountry>[
  ShowCountry('PL', 'Polska'),
  ShowCountry('AL', 'Albania'),
  ShowCountry('AT', 'Austria'),
  ShowCountry('BE', 'Belgia'),
  ShowCountry('BY', 'Białoruś'),
  ShowCountry('BA', 'Bośnia i Hercegowina'),
  ShowCountry('BG', 'Bułgaria'),
  ShowCountry('HR', 'Chorwacja'),
  ShowCountry('ME', 'Czarnogóra'),
  ShowCountry('CZ', 'Czechy'),
  ShowCountry('DK', 'Dania'),
  ShowCountry('EE', 'Estonia'),
  ShowCountry('FI', 'Finlandia'),
  ShowCountry('FR', 'Francja'),
  ShowCountry('GR', 'Grecja'),
  ShowCountry('ES', 'Hiszpania'),
  ShowCountry('NL', 'Holandia'),
  ShowCountry('IE', 'Irlandia'),
  ShowCountry('XK', 'Kosowo'),
  ShowCountry('LT', 'Litwa'),
  ShowCountry('LU', 'Luksemburg'),
  ShowCountry('LV', 'Łotwa'),
  ShowCountry('MK', 'Macedonia Północna'),
  ShowCountry('MD', 'Mołdawia'),
  ShowCountry('DE', 'Niemcy'),
  ShowCountry('NO', 'Norwegia'),
  ShowCountry('PT', 'Portugalia'),
  ShowCountry('RO', 'Rumunia'),
  ShowCountry('RU', 'Rosja', inFci: false),
  ShowCountry('RS', 'Serbia'),
  ShowCountry('SK', 'Słowacja'),
  ShowCountry('SI', 'Słowenia'),
  ShowCountry('CH', 'Szwajcaria'),
  ShowCountry('SE', 'Szwecja'),
  ShowCountry('TR', 'Turcja'),
  ShowCountry('UA', 'Ukraina'),
  ShowCountry('HU', 'Węgry'),
  ShowCountry('IT', 'Włochy'),
];

/// Sąsiedzi (granica lądowa, a dla krajów nordyckich i bałtyckich także bliskie połączenia promowe/mostowe).
const countryNeighbours = <String, List<String>>{
  'PL': ['DE', 'CZ', 'SK', 'UA', 'BY', 'LT', 'RU'],
  'AL': ['ME', 'XK', 'MK', 'GR'],
  'AT': ['DE', 'CZ', 'SK', 'HU', 'SI', 'IT', 'CH'],
  'BE': ['NL', 'DE', 'LU', 'FR'],
  'BY': ['PL', 'LT', 'LV', 'RU', 'UA'],
  'BA': ['HR', 'RS', 'ME'],
  'BG': ['RO', 'RS', 'MK', 'GR', 'TR'],
  'HR': ['SI', 'HU', 'RS', 'BA', 'ME'],
  'ME': ['HR', 'BA', 'RS', 'XK', 'AL'],
  'CZ': ['DE', 'PL', 'SK', 'AT'],
  'DK': ['DE', 'SE'],
  'EE': ['LV', 'FI', 'RU'],
  'FI': ['SE', 'NO', 'EE', 'RU'],
  'FR': ['BE', 'LU', 'DE', 'CH', 'IT', 'ES'],
  'GR': ['AL', 'MK', 'BG', 'TR'],
  'ES': ['FR', 'PT'],
  'NL': ['DE', 'BE'],
  'IE': [],
  'XK': ['AL', 'ME', 'RS', 'MK'],
  'LT': ['LV', 'BY', 'PL', 'RU'],
  'LU': ['BE', 'DE', 'FR'],
  'LV': ['EE', 'LT', 'BY', 'RU'],
  'MK': ['XK', 'RS', 'BG', 'GR', 'AL'],
  'MD': ['RO', 'UA'],
  'DE': ['DK', 'PL', 'CZ', 'AT', 'CH', 'FR', 'LU', 'BE', 'NL'],
  'NO': ['SE', 'FI', 'RU'],
  'PT': ['ES'],
  'RO': ['HU', 'UA', 'MD', 'BG', 'RS'],
  'RU': ['NO', 'FI', 'EE', 'LV', 'LT', 'PL', 'BY', 'UA'],
  'RS': ['HU', 'RO', 'BG', 'MK', 'XK', 'ME', 'BA', 'HR'],
  'SK': ['CZ', 'PL', 'UA', 'HU', 'AT'],
  'SI': ['IT', 'AT', 'HU', 'HR'],
  'CH': ['DE', 'FR', 'IT', 'AT'],
  'SE': ['NO', 'FI', 'DK'],
  'TR': ['GR', 'BG'],
  'UA': ['PL', 'SK', 'HU', 'RO', 'MD', 'BY', 'RU'],
  'HU': ['AT', 'SK', 'UA', 'RO', 'RS', 'HR', 'SI'],
  'IT': ['FR', 'CH', 'AT', 'SI'],
};

ShowCountry countryByCode(String code) =>
    showCountries.firstWhere((c) => c.code == code, orElse: () => ShowCountry(code, code));

List<ShowCountry> neighboursOf(String code) => [for (final c in countryNeighbours[code] ?? const <String>[]) countryByCode(c)];

/// Kraj zamieszkania wybrany przez użytkownika (domyślnie z ustawień telefonu, a gdy nieznany – Polska).
class HomeCountry {
  static const _key = 'valkor_country_v1';
  static const _nbKey = 'valkor_country_neighbours_v1';

  static Future<(String, bool)> load() async {
    final p = await SharedPreferences.getInstance();
    var code = p.getString(_key);
    if (code == null) {
      final sys = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
      code = showCountries.any((c) => c.code == sys && c.inFci) ? sys! : 'PL';
    }
    return (code, p.getBool(_nbKey) ?? true);
  }

  static Future<void> save(String code, bool neighbours) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, code);
    await p.setBool(_nbKey, neighbours);
  }
}

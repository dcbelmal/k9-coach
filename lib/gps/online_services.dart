import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/safe_prefs.dart';
import 'tile_health.dart';
import 'weather.dart';

export 'tile_health.dart';

/// Zgody na usługi online przy treningu GPS – osobne od zgody systemowej
/// na lokalizację. Nagrywanie trasy działa lokalnie bez nich.
///
/// * Pogoda (Open-Meteo): serwis dostaje przybliżone współrzędne (3 miejsca po
///   przecinku, ok. 100 m) i adres IP telefonu.
/// * Mapa (OpenStreetMap): dostawca kafli poznaje oglądany obszar i adres IP.
/// * Mapa terenowa (OpenTopoMap) – osobna zgoda, wybierana na ekranie Valkor Track.
///
/// `null` = jeszcze nie zapytano – wtedy nic nie jest wysyłane.
class OnlineConsent extends ChangeNotifier {
  OnlineConsent._();
  static final OnlineConsent instance = OnlineConsent._();
  static const _key = 'valkor_privacy_v1';

  bool? weather;
  bool? map;

  /// Zgoda na kafle mapy terenowej OpenTopoMap (osobny dostawca).
  bool? topo;

  bool get asked => weather != null && map != null;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      weather = j['weather'] as bool?;
      map = j['map'] as bool?;
      topo = j['topo'] as bool?;
    } catch (e) {
      logError('Zgody online', e);
    }
    notifyListeners();
  }

  Future<void> set({bool? weather, bool? map, bool? topo}) async {
    final old = (this.weather, this.map, this.topo);
    if (weather != null) this.weather = weather;
    if (map != null) this.map = map;
    if (topo != null) this.topo = topo;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await SafePrefs.setString(p, _key, jsonEncode({'weather': this.weather, 'map': this.map, if (this.topo != null) 'topo': this.topo}));
    } catch (e) {
      this.weather = old.$1;
      this.map = old.$2;
      this.topo = old.$3;
      notifyListeners();
      rethrow;
    }
  }
}

/// Usługi zewnętrzne ekranu GPS. W testach podmieniane na atrapy, żeby
/// sprawdzić, że bez zgody nic nie trafia do sieci.
class GpsServices {
  static Future<LocationPermission> Function() checkPermission = Geolocator.checkPermission;
  static Future<bool> Function() serviceEnabled = Geolocator.isLocationServiceEnabled;
  static Future<LocationPermission> Function() requestPermission = Geolocator.requestPermission;
  static Future<Position?> Function() position = _position;
  static Future<Weather?> Function(double lat, double lng) weather = fetchWeather;

  /// Kafle mapy. Bez zgody – brak warstwy, więc brak żądań do dostawcy mapy.
  static Widget Function() tiles = _osmTiles;

  static Future<Position?> _position() async {
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
          );
    } catch (_) {
      return null;
    }
  }

  /// Kafle mapy terenowej (OpenTopoMap, CC-BY-SA; tylko lekki ruch, bez pobierania hurtowego).
  static Widget Function() topoTiles = _topoTiles;

  /// Mapy offline zgodnie z zasadami dostawców: zapamiętujemy tylko kafle
  /// obejrzane online (bez pobierania całych obszarów, którego zabraniają
  /// zasady OpenStreetMap i OpenTopoMap) i używamy ich do 30 dni – także bez
  /// zasięgu. Limit 300 MB, najstarsze kafle są usuwane.
  static const offlineDays = 30;
  static TileProvider? _provider;
  static TileProvider _cached() => _provider ??= NetworkTileProvider(
        cachingProvider: kIsWeb
            ? null
            : BuiltInMapCachingProvider.getOrCreateInstance(
                maxCacheSize: 300 * 1000 * 1000,
                overrideFreshAge: const Duration(days: offlineDays),
              ),
      );

  static Widget _topoTiles() => tileLayer('https://tile.opentopomap.org/{z}/{x}/{y}.png', 17, _cached());

  static Widget _osmTiles() => tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', 19, _cached());

  /// Warstwa kafli z pamięcią podręczną, obsługą błędów i kontrolowanym
  /// ponawianiem ([TileHealth]). Błędne kafle są usuwane, gdy wyjdą poza
  /// ekran, więc przy powrocie wczytują się ponownie.
  static TileLayer tileLayer(String url, int maxZoom, TileProvider provider) => TileLayer(
        urlTemplate: url,
        tileProvider: provider,
        userAgentPackageName: 'pl.k9coach.app',
        maxZoom: maxZoom.toDouble(),
        errorTileCallback: TileHealth.instance.onError,
        tileBuilder: _watch,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
        reset: TileHealth.instance.resetStream,
      );

  /// Liczy wczytane kafle (stan podkładu) – obraz kafla bez zmian.
  static Widget _watch(BuildContext context, Widget tile, TileImage image) {
    TileHealth.instance.onLoaded(image);
    return tile;
  }

  @visibleForTesting
  static void reset() {
    checkPermission = Geolocator.checkPermission;
    serviceEnabled = Geolocator.isLocationServiceEnabled;
    requestPermission = Geolocator.requestPermission;
    position = _position;
    weather = fetchWeather;
    tiles = _osmTiles;
    topoTiles = _topoTiles;
  }
}

/// Warstwa mapy: kafle tylko po zgodzie użytkownika.
Widget mapTiles() => OnlineConsent.instance.map == true ? GpsServices.tiles() : const SizedBox.shrink();

import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/safe_prefs.dart';
import 'weather.dart';

/// Zgody na usługi online przy treningu GPS – osobne od zgody systemowej
/// na lokalizację. Nagrywanie trasy działa lokalnie bez nich.
///
/// * Pogoda (Open-Meteo): serwis dostaje przybliżone współrzędne (3 miejsca po
///   przecinku, ok. 100 m) i adres IP telefonu.
/// * Mapa (OpenStreetMap): dostawca kafli poznaje oglądany obszar i adres IP.
///
/// `null` = jeszcze nie zapytano – wtedy nic nie jest wysyłane.
class OnlineConsent extends ChangeNotifier {
  OnlineConsent._();
  static final OnlineConsent instance = OnlineConsent._();
  static const _key = 'valkor_privacy_v1';

  bool? weather;
  bool? map;

  bool get asked => weather != null && map != null;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      weather = j['weather'] as bool?;
      map = j['map'] as bool?;
    } catch (e) {
      logError('Zgody online', e);
    }
    notifyListeners();
  }

  Future<void> set({bool? weather, bool? map}) async {
    final old = (this.weather, this.map);
    if (weather != null) this.weather = weather;
    if (map != null) this.map = map;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await SafePrefs.setString(p, _key, jsonEncode({'weather': this.weather, 'map': this.map}));
    } catch (e) {
      this.weather = old.$1;
      this.map = old.$2;
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

  static Widget _osmTiles() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'pl.k9coach.app',
        maxZoom: 19,
      );

  @visibleForTesting
  static void reset() {
    checkPermission = Geolocator.checkPermission;
    serviceEnabled = Geolocator.isLocationServiceEnabled;
    requestPermission = Geolocator.requestPermission;
    position = _position;
    weather = fetchWeather;
    tiles = _osmTiles;
  }
}

/// Warstwa mapy: kafle tylko po zgodzie użytkownika.
Widget mapTiles() => OnlineConsent.instance.map == true ? GpsServices.tiles() : const SizedBox.shrink();

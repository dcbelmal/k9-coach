// Aktualność pozycji psa zależna od trybu pracy trackera Valkor Track.
//
// W trybie SPORT tracker wysyła każdy pomiar GNSS (1 Hz), więc pozycja sprzed
// kilku sekund jest już nieaktualna. Progi są stałe dla trybu (nie wydłużają
// się same, gdy tracker zwalnia – wtedy pozycja ma po prostu być nieaktualna).
import 'valkor_proto.dart';

/// Ocena wieku pozycji psa.
enum Freshness {
  /// Pozycja aktualna.
  live,

  /// Opóźnienie – pozycja jeszcze pokazywana, ale z ostrzeżeniem.
  delayed,

  /// Brak aktualnej pozycji (ostatnia znana pozycja z czasem pomiaru).
  stale,

  /// Wyraźne ostrzeżenie: od dłuższego czasu brak nowych danych.
  noData,
}

/// Progi aktualności (s) dla trybu pracy trackera.
class FreshnessLimits {
  /// Do tylu sekund pozycja jest aktualna.
  final double liveSec;

  /// Do tylu sekund – opóźnienie; powyżej – brak aktualnej pozycji.
  final double delayedSec;

  /// Powyżej tylu sekund – wyraźne ostrzeżenie o braku nowych danych.
  final double warnSec;

  /// Po tylu sekundach bez żadnego pakietu Valkor (przy działającym
  /// Bluetooth) kanał uznajemy za niemy – aplikacja przyjmuje wtedy
  /// pozycje Meshtastic jako tryb awaryjny.
  final double channelSilentSec;

  const FreshnessLimits(this.liveSec, this.delayedSec, this.warnSec, this.channelSilentSec);

  /// SPORT i SEARCH: pomiar co 1 s, pakiet Status co ~1,5 s bez fixu.
  static const sport = FreshnessLimits(3, 5, 10, 5);

  /// WALK: pozycja co 5 s, Status co ~7,5 s bez fixu.
  static const walk = FreshnessLimits(8, 12, 20, 20);

  /// ECO: pozycja co 30 s, Status co ~45 s bez fixu.
  static const eco = FreshnessLimits(35, 45, 90, 100);

  static FreshnessLimits of(ValkorMode? m) => switch (m) {
        ValkorMode.walk => walk,
        ValkorMode.eco => eco,
        ValkorMode.sport || ValkorMode.search || null => sport,
      };

  /// Progi dla zwykłego Meshtastic (pozycja co interwał rozgłaszania,
  /// zwykle dziesiątki sekund): aktualna do [liveLimitSec], potem ostatnia
  /// znana pozycja – jak w wersjach przed 0.27.1 (bez stanu „brak danych”).
  factory FreshnessLimits.mesh(double liveLimitSec) =>
      FreshnessLimits(liveLimitSec, liveLimitSec, double.infinity, double.infinity);

  Freshness classify(double ageSec) {
    if (ageSec <= liveSec) return Freshness.live;
    if (ageSec <= delayedSec) return Freshness.delayed;
    if (ageSec <= warnSec) return Freshness.stale;
    return Freshness.noData;
  }

  /// Przerwa w pomiarach (s), po której trasa psa zaczyna nowy odcinek:
  /// kilka brakujących pomiarów w trybie trackera (SPORT: 5 s).
  double get trackGapSec => delayedSec;
}

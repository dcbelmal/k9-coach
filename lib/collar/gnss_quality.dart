// Ocena jakości pozycji GNSS trackera (Valkor Coach 0.27.2).
//
// Rozdziela cztery rzeczy, które wcześniej zlewały się w jedno „zielone”:
//  1. aktualność pomiaru (freshness.dart – czas, nie jakość);
//  2. wiarygodność współrzędnych (ten plik: GnssQuality);
//  3. wiarygodność odległości do psa (DistanceView – z obu urządzeń);
//  4. stan Bluetooth (CollarLink).
//
// Zasady:
//  * Deklarowana dokładność trackera (firmware 0.1.x: HDOP × 3 m) NIE jest
//    zmierzonym błędem. Test A: deklarowane 1,32 m, rzeczywisty błąd 5–8 m.
//    Dlatego realistyczna niepewność [GnssAssessment.sigmaM] ma dolną granicę
//    i rośnie przy słabej geometrii, małej liczbie satelitów i po odzyskaniu
//    sygnału. Gdy odbiornik poda własny błąd (GST, firmware 0.1.2), bierzemy go,
//    ale nigdy poniżej granicy.
//  * Stabilne współrzędne nie są dowodem poprawności (test D: 37 s stabilnie
//    złej pozycji 183 m obok). Po odzyskaniu sygnału niepewność jest
//    powiększona przez [recoveryWindowSec], niezależnie od spójności pomiarów.
//  * Skok niewytłumaczalny prędkością (test D: 178 m w 1 s przy 0,03 m/s) to
//    korekta pozycji, nie ruch psa: nowy odcinek trasy, ponowna stabilizacja.
//    Nowa pozycja NIE jest odrzucana na stałe – po serii spójnych pomiarów
//    staje się wiarygodna.
//  * Identyczne współrzędne z nowym czasem to zwykle postój – nie błąd.
//    Długi ciąg identycznych współrzędnych przy słabej jakości oznaczamy
//    jako „pozycja zatrzymana” (bez odrzucania).
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import 'valkor_proto.dart';

/// Stan pozycji GNSS jednego urządzenia.
enum GnssState {
  /// Brak sygnału GNSS (tracker zgłasza utratę albo brak pomiarów).
  noSignal,

  /// Wyszukiwanie satelitów (jeszcze żadnego pomiaru).
  searching,

  /// Pomiar jest, ale słabej jakości (geometria, satelity, duży błąd).
  weak,

  /// Stabilizacja po starcie / odzyskaniu sygnału / korekcie.
  stabilizing,

  /// Wiarygodna pozycja.
  reliable,

  /// Podejrzana zmiana współrzędnych (korekta, niespójność).
  suspect,

  /// Pierwsze pomiary po odzyskaniu sygnału (część stabilizacji).
  recovered;

  String get csv => switch (this) {
        noSignal => 'brak_sygnalu',
        searching => 'wyszukiwanie',
        weak => 'slaba_jakosc',
        stabilizing => 'stabilizacja',
        reliable => 'wiarygodna',
        suspect => 'podejrzana',
        recovered => 'odzyskanie',
      };
}

/// Wynik oceny jednego pomiaru.
class GnssAssessment {
  final GnssState state;

  /// Realistyczna niepewność pozycji (m, ~68%), nie mniejsza niż granica.
  final double sigmaM;

  /// Korekta pozycji (skok niewytłumaczalny ruchem) – przerywa trasę.
  final bool correction;

  /// Ciąg identycznych współrzędnych przy słabej jakości (odbiornik trzyma pozycję).
  final bool frozen;

  /// Długość ciągu identycznych współrzędnych (pomiary).
  final int sameRun;

  /// W oknie po odzyskaniu sygnału / korekcie.
  final bool recovering;

  /// Przesunięcie od poprzedniego pomiaru (m) i odstęp (s).
  final double? jumpM, gapSec;

  /// Kod przyczyny zmiany oceny (CSV) – null, gdy bez zmian.
  final String? changeReason;

  /// Skąd niepewność: „gst” (odbiornik), „hdop” (HDOP × 3 m), „brak”.
  final String sigmaSource;
  const GnssAssessment(this.state, this.sigmaM,
      {this.correction = false,
      this.frozen = false,
      this.sameRun = 0,
      this.recovering = false,
      this.jumpM,
      this.gapSec,
      this.changeReason,
      this.sigmaSource = 'hdop'});

  bool get usable => state == GnssState.reliable || state == GnssState.weak;
}

/// Ocena jakości pozycji trackera na psie.
class GnssQuality {
  /// Najmniejsza przyjmowana niepewność trackera (m), gdy dokładność to
  /// HDOP × 3 m. Test A: deklarowane 1,3 m, rzeczywisty błąd 5–8 m.
  static const floorHdopM = 4.0;

  /// Najmniejsza niepewność, gdy odbiornik sam podał błąd (GST).
  static const floorGstM = 2.5;

  /// Okno po odzyskaniu sygnału / korekcie (s) z dodatkową niepewnością.
  final double recoveryWindowSec;

  /// Dodatkowa niepewność na początku okna (m), maleje liniowo do zera.
  static const recoveryPadM = 30.0;

  /// Przerwa w pomiarach (s), po której następny pomiar to odzyskanie sygnału.
  final double recoveryGapSec;

  /// Słaba jakość: niepewność powyżej tylu metrów albo HDOP / satelity poniżej.
  static const weakSigmaM = 15.0;
  static const weakHdop = 4.0;
  static const weakSats = 6;

  /// Ile identycznych pomiarów z rzędu przy słabej jakości = „pozycja zatrzymana”.
  static const frozenRun = 10;

  /// Ile kolejnych dobrych, spójnych pomiarów kończy stabilizację i ile
  /// sekund co najmniej trwa stabilizacja (pomiar co 1 s).
  final int needGood;
  final double minStabilizeSec;

  GnssQuality({this.needGood = 5, this.minStabilizeSec = 10, this.recoveryWindowSec = 60, this.recoveryGapSec = 5});

  /// Tracker Valkor (1 Hz).
  factory GnssQuality.valkor() => GnssQuality();

  /// Zwykły Meshtastic (pozycja co 5–60 s): zachowanie jak przed 0.27.2
  /// (stabilizacja wg FixTrust), z realistyczną dolną granicą niepewności
  /// i wykrywaniem słabej jakości, bez okna odzyskania (za rzadkie pomiary).
  factory GnssQuality.mesh() => GnssQuality(needGood: 1, minStabilizeSec: 0, recoveryWindowSec: 0, recoveryGapSec: 90);

  GnssState state = GnssState.searching;
  String reason = 'pierwsze_pomiary';
  LatLng? _last;
  DateTime? _lastAt;
  double? _lastSpeed;
  DateTime? _recoveryAt;
  int _good = 0;
  int sameRun = 0;
  int corrections = 0, recoveries = 0, frozenEvents = 0;
  GnssAssessment? lastAssessment;

  void reset(String why) {
    state = GnssState.searching;
    reason = why;
    _last = null;
    _lastAt = null;
    _lastSpeed = null;
    _recoveryAt = null;
    _good = 0;
    sameRun = 0;
  }

  /// Tracker zgłosił brak fixu (pakiet Status) albo brak pomiarów.
  void noFix({required bool everHadFix}) {
    final s = everHadFix ? GnssState.noSignal : GnssState.searching;
    if (state != s) reason = everHadFix ? 'utrata_sygnalu' : 'wyszukiwanie';
    state = s;
    _good = 0;
  }

  /// Ocena pomiaru. [detail] – surowe dane odbiornika (firmware 0.1.2) dla
  /// tego albo poprzedniego pomiaru (GST zmienia się powoli).
  GnssAssessment add(LatLng ll, DateTime at,
      {double? accuracyM, double? hdop, int? sats, double? speedMs, ValkorFixDetail? detail, bool accFromHdop = true}) {
    final prev = _last, prevAt = _lastAt;
    final gap = prevAt == null ? null : at.difference(prevAt).inMilliseconds / 1000;
    final jump = prev == null ? null : const Distance()(prev, ll);
    String? change;

    // Odzyskanie sygnału: pierwszy pomiar po przerwie (albo w ogóle).
    final wasLost = state == GnssState.noSignal || state == GnssState.searching;
    if (prev == null || gap == null || gap >= recoveryGapSec || wasLost) {
      _recoveryAt = at;
      _good = 0;
      recoveries++;
      change = prev == null ? 'pierwszy_pomiar' : 'odzyskanie_sygnalu';
    }

    // Korekta: przesunięcie niewytłumaczalne prędkością i czasem.
    var correction = false;
    if (prev != null && gap != null && gap > 0 && gap < recoveryGapSec) {
      final v = math.max(speedMs ?? 0, _lastSpeed ?? 0);
      final allowed = (v + 5) * math.max(gap, 1) + 20;
      if (jump! > allowed) {
        correction = true;
        corrections++;
        _recoveryAt = at;
        _good = 0;
        change = 'korekta_pozycji';
      }
    }

    // Identyczne współrzędne (surowe, gdy firmware je podaje).
    final same = prev != null && (prev.latitude - ll.latitude).abs() < 1e-7 && (prev.longitude - ll.longitude).abs() < 1e-7;
    sameRun = detail != null && detail.has(ValkorDetailFlags.rawAvailable) ? detail.sameRawRun : (same ? sameRun + 1 : 0);

    // Realistyczna niepewność.
    final gst = detail?.gstHorizontalM;
    var sigma = gst != null ? math.max(gst, floorGstM) : math.max(accuracyM ?? 10, floorHdopM);
    final src = gst != null ? 'gst' : (accuracyM == null ? 'brak' : (accFromHdop ? 'hdop' : 'odbiornik'));
    if (sats != null && sats > 0) {
      if (sats < weakSats) {
        sigma *= 2.5;
      } else if (sats < 8) {
        sigma *= 1.5;
      }
    }
    if (hdop != null && hdop > 2) sigma *= hdop / 2;
    final weakNow = sigma > weakSigmaM || (hdop != null && hdop > weakHdop) || (sats != null && sats > 0 && sats < weakSats);
    final frozen = weakNow && sameRun >= frozenRun;
    if (frozen && sameRun == frozenRun) frozenEvents++;
    if (frozen) sigma += 10;
    final ra = _recoveryAt;
    final recAge = ra == null ? null : at.difference(ra).inMilliseconds / 1000;
    final recovering = recAge != null && recAge < recoveryWindowSec;
    if (recovering) sigma += recoveryPadM * (1 - recAge / recoveryWindowSec);

    // Stan.
    GnssState s;
    if (correction) {
      s = GnssState.suspect;
    } else if (weakNow) {
      _good = 0;
      s = GnssState.weak;
      change ??= state != GnssState.weak ? 'slaba_jakosc' : null;
    } else {
      _good++;
      final longEnough = recAge == null || recAge >= minStabilizeSec;
      if (_good >= needGood && longEnough) {
        s = GnssState.reliable;
        if (state != GnssState.reliable) change ??= 'stabilizacja_zakonczona';
      } else {
        s = (change == 'odzyskanie_sygnalu' || state == GnssState.recovered) && _good < needGood
            ? GnssState.recovered
            : GnssState.stabilizing;
      }
    }
    if (change != null) reason = change;
    state = s;
    _last = ll;
    _lastAt = at;
    _lastSpeed = speedMs;
    final a = GnssAssessment(s, sigma,
        correction: correction,
        frozen: frozen,
        sameRun: sameRun,
        recovering: recovering,
        jumpM: jump,
        gapSec: gap,
        changeReason: change,
        sigmaSource: src);
    lastAssessment = a;
    return a;
  }

  /// Opis stanu do interfejsu (null = wiarygodna).
  String? get why => switch (state) {
        GnssState.reliable => null,
        GnssState.weak => tr('Niska dokładność lokalizacji'),
        GnssState.suspect => tr('Podejrzana pozycja GPS'),
        GnssState.noSignal => tr('brak sygnału GPS'),
        GnssState.searching => tr('wyszukiwanie satelitów'),
        GnssState.stabilizing || GnssState.recovered => tr('Stabilizacja GPS'),
      };
}

/// Niezgodność GNSS i Bluetooth: silny sygnał BLE (urządzenia blisko) przy
/// dużej odległości z GPS. RSSI to tylko sygnał pomocniczy – nigdy nie
/// zastępuje odległości, nie zeruje jej i nie ogranicza.
class BleCheck {
  /// RSSI (dBm) co najmniej tyle = urządzenia bardzo blisko (kilka metrów).
  static const strongRssi = -55;

  /// RSSI (dBm) co najmniej tyle wspiera ocenę „pies w pobliżu”.
  static const nearRssi = -62;

  /// Najstarszy pomiar RSSI, którego używamy (s).
  static const maxAgeSec = 10.0;

  /// Przy działającym Bluetooth odległość większa niż tyle (m) jest
  /// fizycznie niemożliwa dla T1000-E (zasięg BLE ~100 m w terenie).
  static const maxBleRangeM = 400.0;

  /// Czy GPS przeczy Bluetooth. [rssi] – ostatni pomiar, [rssiAgeSec] – jego wiek.
  static bool conflict(double distanceM, double uncertaintyM, int? rssi, double? rssiAgeSec) {
    if (rssi == null || rssi == 0 || rssiAgeSec == null || rssiAgeSec > maxAgeSec) return false;
    if (rssi >= strongRssi && distanceM > math.max(30, 3 * uncertaintyM + 15)) return true;
    return distanceM > maxBleRangeM;
  }

  /// Czy Bluetooth wspiera ocenę „pies w pobliżu” (GPS mówi: blisko w granicach 2σ).
  static bool supportsNearby(double distanceM, double uncertaintyM, int? rssi, double? rssiAgeSec) {
    if (rssi == null || rssi == 0 || rssiAgeSec == null || rssiAgeSec > maxAgeSec) return false;
    return rssi >= nearRssi && distanceM <= 2 * uncertaintyM + 10;
  }
}

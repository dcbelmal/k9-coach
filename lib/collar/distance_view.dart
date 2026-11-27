import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../gps/phone_location.dart';
import 'collar_link.dart';

/// Co pokazujemy w miejscu odległości do psa.
enum DistanceState {
  /// Brak jakiejkolwiek pozycji psa.
  noDog,

  /// Pozycja psa jest, ale nie ma aktualnej lokalizacji telefonu.
  waitingPhone,

  /// Pozycje są, ale jeszcze niewiarygodne (start, połączenie, wyjście
  /// z budynku, powrót GPS po przerwie) – „Stabilizacja GPS”.
  stabilizing,

  /// Pozycja psa podejrzana: korekta GNSS albo sprzeczność GPS z Bluetooth
  /// (silny sygnał BLE przy dużej odległości z GPS) – „Podejrzana pozycja GPS”.
  suspect,

  /// Słaba jakość pozycji psa lub telefonu – „Niska dokładność lokalizacji”,
  /// bez dokładnej liczby metrów.
  lowAccuracy,

  /// Niepewność większa niż sama odległość albo bardzo duża – „Brak
  /// wiarygodnej odległości”.
  unreliable,

  /// Odległość mieści się w błędzie GPS – „Pies w pobliżu”.
  nearby,

  /// Wiarygodna odległość z niepewnością.
  estimate,

  /// Pies nie jest na żywo (np. utrata Bluetooth): ostatnia znana pozycja
  /// i jej wiek, odległość od bieżącej pozycji telefonu.
  lastKnown,
}

/// Jedna prezentacja odległości dla ekranu spaceru i Valkor Track.
///
/// Odległość zawsze z GPS, z błędem – nigdy zerowana ani liczona
/// z siły sygnału Bluetooth. Gdy pozycja telefonu jest nieaktualna,
/// mówimy to wprost zamiast pokazywać liczbę ze starych danych.
class DistanceView {
  final DistanceState state;
  final double? m, uncertaintyM;
  final DogDistance? dd;

  /// Wiek ostatniej znanej pozycji psa (s) – dla [DistanceState.lastKnown].
  final double? lastAgeSec;

  /// Dlaczego nie ma odległości (do diagnostyki), null = jest.
  final String? reason;

  /// Sprzeczność GPS z Bluetooth (silny sygnał BLE przy dużej odległości z GPS).
  final bool bleConflict;

  /// Bluetooth wspiera ocenę „pies w pobliżu”.
  final bool bleNear;

  const DistanceView(this.state,
      {this.m, this.uncertaintyM, this.dd, this.lastAgeSec, this.reason, this.bleConflict = false, this.bleNear = false});

  /// Odległość pokazywana jako liczba (z niepewnością).
  bool get hasDistance =>
      m != null && (state == DistanceState.estimate || state == DistanceState.nearby || state == DistanceState.lastKnown);

  /// Odległość na tyle wiarygodna, żeby uruchomić alarm oddalenia.
  bool get alarmable => state == DistanceState.estimate;

  /// Nazwa stanu do CSV.
  String get csv => switch (state) {
        DistanceState.noDog => 'brak_psa',
        DistanceState.waitingPhone => 'czeka_na_telefon',
        DistanceState.stabilizing => 'stabilizacja',
        DistanceState.suspect => 'podejrzana',
        DistanceState.lowAccuracy => 'niska_dokladnosc',
        DistanceState.unreliable => 'brak_wiarygodnej',
        DistanceState.nearby => 'w_poblizu',
        DistanceState.estimate => 'odleglosc',
        DistanceState.lastKnown => 'ostatnia_znana',
      };

  /// Duży napis: „Pies w pobliżu”, „12 m ± 7 m”, „Oczekiwanie na lokalizację telefonu”…
  String get text => switch (state) {
        DistanceState.noDog => tr('Czekam na pozycję psa…'),
        DistanceState.waitingPhone => tr('Oczekiwanie na lokalizację telefonu'),
        DistanceState.stabilizing => tr('Stabilizacja GPS'),
        DistanceState.suspect => tr('Podejrzana pozycja GPS'),
        DistanceState.lowAccuracy => tr('Niska dokładność lokalizacji'),
        DistanceState.unreliable => tr('Brak wiarygodnej odległości'),
        DistanceState.nearby => tr('Pies w pobliżu'),
        DistanceState.estimate => fmtDistance(m!, uncertaintyM),
        DistanceState.lastKnown => m == null ? '–' : fmtDistance(m!, uncertaintyM),
      };

  /// Zdanie do karty spaceru: „Pies 12 m ± 7 m od Ciebie” itd.
  String get sentence => switch (state) {
        DistanceState.noDog => tr('Czekam na pozycję psa…'),
        DistanceState.waitingPhone => tr('Oczekiwanie na lokalizację telefonu'),
        DistanceState.stabilizing => tr('Stabilizacja GPS'),
        DistanceState.suspect => tr('Podejrzana pozycja GPS'),
        DistanceState.lowAccuracy => tr('Niska dokładność lokalizacji'),
        DistanceState.unreliable => tr('Brak wiarygodnej odległości'),
        DistanceState.nearby => tr('Pies w pobliżu'),
        DistanceState.estimate => tr('Pies {0} od Ciebie', [text]),
        DistanceState.lastKnown => m == null
            ? tr('Ostatnia znana pozycja psa')
            : tr('Ostatnia znana pozycja: {0} od Ciebie', [text]),
      };

  /// Objaśnienie: z której chwili i jak pewna jest odległość.
  String? get note {
    final d = dd;
    switch (state) {
      case DistanceState.nearby:
        return tr('Odległość mieści się w błędzie GPS telefonu i trackera (do ~{0} m) – dokładniej się nie da.',
            [d!.nearbyRadiusM!.round()]);
      case DistanceState.estimate:
        if (d == null) return null;
        if (d.matchedM != null && d.ageSec >= 8) {
          return tr('Odległość w chwili pomiaru psa ({0} s temu). Pies mógł się od tego czasu przesunąć.', [d.ageSec.round()]);
        }
        if (d.matchedM == null && d.ageSec >= 8) {
          return tr('Pozycja psa sprzed {0} s porównana z Twoją bieżącą – odległość przybliżona.', [d.ageSec.round()]);
        }
        return null;
      case DistanceState.waitingPhone:
        return reason == null ? null : tr('Odległość wróci, gdy telefon poda aktualną pozycję ({0}).', [reason!]);
      case DistanceState.stabilizing:
        return reason == null ? null : tr('Odległość pojawi się, gdy pozycja będzie wiarygodna ({0}).', [reason!]);
      case DistanceState.suspect:
        return bleConflict
            ? tr('GPS wskazuje ok. {0} m, ale sygnał Bluetooth jest bardzo silny – możliwy błąd lokalizacji.', [(m ?? 0).round()])
            : tr('Nagła zmiana pozycji psa niewytłumaczalna ruchem – możliwa korekta GPS. Czekam na potwierdzenie.');
      case DistanceState.lowAccuracy:
      case DistanceState.unreliable:
        final mm = m, u = uncertaintyM;
        if (mm == null || u == null) return reason;
        final lo = math.max(0.0, mm - 2 * u), hi = mm + 2 * u;
        return tr('Możliwa odległość: {0}–{1} m ({2}).', [lo.round(), hi.round(), reason ?? '']);
      // Wiek ostatniej znanej pozycji ekrany pokazują w wierszu stanu psa.
      case DistanceState.lastKnown:
      case DistanceState.noDog:
        return null;
    }
  }

  /// Największa niepewność (m), przy której pokazujemy liczbę metrów.
  static const maxShownUncertaintyM = 25.0;

  /// Odległość do psa [dogId] w chwili [now].
  static DistanceView of(CollarLink c, String dogId, {required DateTime now}) {
    final link = c.status(now: now, dogId: dogId);
    final node = c.nodeOf(dogId);
    final last = c.lastKnown(dogId);
    final LatLng? dogLl = node?.displayLl ?? last?.ll;
    if (dogLl == null) return const DistanceView(DistanceState.noDog, reason: 'brak pozycji psa');
    final track = HandlerTrack.instance;
    if (link.current) {
      final dd = c.distanceTo(dogId, now: now);
      final m = dd?.bestM;
      if (dd == null || m == null) {
        return DistanceView(DistanceState.waitingPhone,
            reason: DogDistance.whyNot(node?.fix, track, now: now) ?? tr('brak lokalizacji telefonu'));
      }
      final u = dd.bestUncertaintyM ?? (DogDistance.unknownDogAccM + DogDistance.unknownPhoneAccM);
      final rssiAt = c.diag.bleRssiAt;
      final rssiAge = rssiAt == null ? null : now.difference(rssiAt).inMilliseconds / 1000;
      final conflict = BleCheck.conflict(m, u, c.diag.bleRssi, rssiAge);
      final bleNear = BleCheck.supportsNearby(m, u, c.diag.bleRssi, rssiAge);
      // Stabilizacja: pojedynczy pomiar nie wystarcza – bez liczby, która
      // może być błędna (np. 113 m tuż po wyjściu z budynku).
      final why = unstableReason(c, dogId);
      if (why != null) return DistanceView(DistanceState.stabilizing, m: m, uncertaintyM: u, dd: dd, reason: why, bleConflict: conflict);
      final dogQ = node?.fix?.gnssState;
      // GPS przeczy Bluetooth albo korekta pozycji: obniżona pewność, bez liczby.
      if (conflict || dogQ == GnssState.suspect) {
        return DistanceView(DistanceState.suspect, m: m, uncertaintyM: u, dd: dd, bleConflict: conflict,
            reason: conflict ? tr('sprzeczność GPS i Bluetooth') : tr('korekta pozycji GPS'));
      }
      final phoneWeak = (HandlerTrack.instance.last?.accuracyM ?? 0) > PhoneLocation.weakAccuracyM;
      final dogWeak = dogQ == GnssState.weak || dogQ == GnssState.noSignal;
      // Pies w pobliżu: odległość w granicach błędu obu GPS (niepewność ≤ 12 m)
      // albo GPS mówi „blisko w granicach 2σ” i Bluetooth to potwierdza.
      if (!dogWeak && !phoneWeak && (dd.withinError || (bleNear && u <= 2 * DogDistance.nearbyMaxUncertaintyM))) {
        return DistanceView(DistanceState.nearby, m: m, uncertaintyM: u, dd: dd, bleNear: bleNear);
      }
      if (dogWeak || phoneWeak) {
        return DistanceView(DistanceState.lowAccuracy, m: m, uncertaintyM: u, dd: dd,
            reason: [if (dogWeak) tr('tracker: słaby sygnał GPS'), if (phoneWeak) tr('telefon: słaby sygnał GPS')].join('; '));
      }
      // Niepewność porównywalna z odległością – liczba byłaby myląca.
      if (u > maxShownUncertaintyM || u > m) {
        return DistanceView(u > m ? DistanceState.unreliable : DistanceState.lowAccuracy, m: m, uncertaintyM: u, dd: dd,
            reason: tr('niepewność ±{0} m', [u.round()]));
      }
      return DistanceView(DistanceState.estimate, m: m, uncertaintyM: u, dd: dd);
    }
    // Nie na żywo: ostatnia znana pozycja i jej wiek.
    final at = last?.at ?? node?.fix?.fixAt;
    final age = at == null ? null : math.max(0.0, now.difference(at).inMilliseconds / 1000);
    final me = track.last;
    final phoneAge = me == null ? null : now.difference(me.at).inMilliseconds / 1000;
    if (me == null || phoneAge! > DogDistance.phoneFreshSec || !PhoneLocation.instance.trust.stable) {
      return DistanceView(DistanceState.lastKnown,
          lastAgeSec: age,
          reason: me == null
              ? tr('brak lokalizacji telefonu')
              : phoneAge! > DogDistance.phoneFreshSec
                  ? tr('pozycja telefonu nieaktualna ({0} s)', [phoneAge.round()])
                  : tr('telefon: {0}', [PhoneLocation.instance.trust.why ?? '']));
    }
    final m = const Distance()(me.best, dogLl);
    final phoneAcc = me.filteredAccM ?? me.accuracyM ?? DogDistance.unknownPhoneAccM;
    final dogAcc = node?.displayAccM ?? DogDistance.unknownDogAccM;
    return DistanceView(DistanceState.lastKnown,
        m: m, uncertaintyM: math.sqrt(phoneAcc * phoneAcc + dogAcc * dogAcc), lastAgeSec: age, reason: tr('pies nie jest na żywo'));
  }
}

/// Dlaczego pozycje psa [dogId] i telefonu nie są jeszcze wiarygodne
/// (null = obie wiarygodne).
String? unstableReason(CollarLink c, String dogId) {
  final phone = PhoneLocation.instance.trust;
  final dog = c.nodeOf(dogId);
  final parts = [
    if (!phone.stable) tr('telefon: {0}', [phone.why ?? '']),
    if (dog != null && dog.fix != null && dog.fix!.gnssState != GnssState.suspect && !(dog.trust.stable && dog.fix!.trusted))
      tr('tracker: {0}', [dog.trust.why ?? '']),
    // Stabilizacja GNSS po starcie / odzyskaniu sygnału / korekcie (0.27.2):
    // spójne, ale jeszcze niepotwierdzone pomiary (test D: 37 s stabilnie złej pozycji).
    if (dog != null && dog.fix != null && dog.trust.stable && dog.fix!.trusted &&
        (dog.fix!.gnssState == GnssState.stabilizing || dog.fix!.gnssState == GnssState.recovered))
      tr('tracker: {0}', [tr('stabilizacja po odzyskaniu sygnału')]),
  ];
  return parts.isEmpty ? null : parts.join('; ');
}

/// „45 s temu”, „3 min temu”, „2 godz. temu” – wiek pozycji.
String fmtAgo(double sec) {
  final s = sec.round();
  if (s < 60) return tr('{0} s temu', [s < 0 ? 0 : s]);
  if (s < 3600) return tr('{0} min temu', [s ~/ 60]);
  if (s < 172800) return tr('{0} godz. temu', [s ~/ 3600]);
  return tr('{0} dni temu', [s ~/ 86400]);
}

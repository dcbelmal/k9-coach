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
  /// z budynku, powrót GPS po przerwie) – „Ustalanie pozycji GPS”.
  stabilizing,

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

  const DistanceView(this.state, {this.m, this.uncertaintyM, this.dd, this.lastAgeSec, this.reason});

  bool get hasDistance =>
      m != null && state != DistanceState.waitingPhone && state != DistanceState.noDog && state != DistanceState.stabilizing;

  /// Duży napis: „Pies w pobliżu”, „12 m ± 7 m”, „Oczekiwanie na lokalizację telefonu”…
  String get text => switch (state) {
        DistanceState.noDog => tr('Czekam na pozycję psa…'),
        DistanceState.waitingPhone => tr('Oczekiwanie na lokalizację telefonu'),
        DistanceState.stabilizing => tr('Ustalanie pozycji GPS'),
        DistanceState.nearby => tr('Pies w pobliżu'),
        DistanceState.estimate => fmtDistance(m!, uncertaintyM),
        DistanceState.lastKnown => m == null ? '–' : fmtDistance(m!, uncertaintyM),
      };

  /// Zdanie do karty spaceru: „Pies 12 m ± 7 m od Ciebie” itd.
  String get sentence => switch (state) {
        DistanceState.noDog => tr('Czekam na pozycję psa…'),
        DistanceState.waitingPhone => tr('Oczekiwanie na lokalizację telefonu'),
        DistanceState.stabilizing => tr('Ustalanie pozycji GPS'),
        DistanceState.nearby => tr('Pies w pobliżu'),
        DistanceState.estimate => tr('Pies {0} od Ciebie', [text]),
        DistanceState.lastKnown => m == null
            ? tr('Ostatnia znana pozycja psa')
            : tr('Ostatnio {0} od Ciebie', [text]),
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
      // Wiek ostatniej znanej pozycji ekrany pokazują w wierszu stanu psa.
      case DistanceState.lastKnown:
      case DistanceState.noDog:
        return null;
    }
  }

  /// Odległość do psa [dogId] w chwili [now].
  static DistanceView of(CollarLink c, String dogId, {required DateTime now}) {
    final link = c.status(now: now, dogId: dogId);
    final node = c.nodeOf(dogId);
    final last = c.lastKnown(dogId);
    final LatLng? dogLl = node?.displayLl ?? last?.ll;
    if (dogLl == null) return const DistanceView(DistanceState.noDog, reason: 'brak pozycji psa');
    final track = HandlerTrack.instance;
    if (link == DogLink.live) {
      final dd = c.distanceTo(dogId, now: now);
      final m = dd?.bestM;
      if (dd == null || m == null) {
        return DistanceView(DistanceState.waitingPhone,
            reason: DogDistance.whyNot(node?.fix, track, now: now) ?? tr('brak lokalizacji telefonu'));
      }
      // Stabilizacja: pojedynczy pomiar nie wystarcza – bez liczby, która
      // może być błędna (np. 113 m tuż po wyjściu z budynku).
      final why = unstableReason(c, dogId);
      if (why != null) return DistanceView(DistanceState.stabilizing, dd: dd, reason: why);
      if (dd.withinError) return DistanceView(DistanceState.nearby, m: m, uncertaintyM: dd.bestUncertaintyM, dd: dd);
      return DistanceView(DistanceState.estimate, m: m, uncertaintyM: dd.bestUncertaintyM, dd: dd);
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
    if (dog != null && dog.fix != null && !(dog.trust.stable && dog.fix!.trusted)) tr('tracker: {0}', [dog.trust.why ?? '']),
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

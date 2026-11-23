import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../gps/dog_stats.dart';
import '../gps/track.dart';
import '../models.dart';
import '../nutrition/energy.dart';

/// Obliczenia Valkor Performance – funkcje czyste, bez zapisu i interfejsu.
///
/// Zasady:
/// * liczymy tylko z prawdziwych pomiarów; brak danych = brak wartości (null),
///   nigdy wartość zgadnięta ani losowa;
/// * przez przerwy w sygnale nie liczymy dystansu ani czasu ruchu;
/// * kalorie są szacunkiem modelu, nie pomiarem.
///
/// Źródła modeli:
/// * Taylor, Heglund, Maloiy 1982, J Exp Biol 97:1–21 – koszt netto
///   przemieszczania się ssaków (w tym psów) 10,7 × M^−0,316 J/(kg·m),
///   prawie niezależny od prędkości w obrębie chodu;
/// * Heglund, Taylor, McMahon 1974, Science 186:1112 – prędkość przejścia
///   kłus → galop 1,53 × M^0,24 m/s;
/// * Alexander, Jayes 1983, J Zool 201:135 – ssaki czworonożne zmieniają chód
///   przy podobnej liczbie Froude’a v²/(g·h): stęp → kłus ok. 0,5,
///   kłus → galop ok. 2,5 (h = wysokość biodra ≈ wysokość w kłębie);
/// * NRC 2006 – RER = 70 × M^0,75 kcal/dzień.

/// Strefy aktywności – orientacyjne, wg rodzaju chodu, nie wg zmęczenia.
enum PerfZone { rest, low, moderate, high }

const _g = 9.81;
const _d = Distance();

/// Progi stref dla konkretnego psa (m/s).
class GaitZones {
  /// Poniżej – odpoczynek / postój (z szumem GPS).
  final double restBelow;

  /// Stęp → kłus.
  final double walkTrot;

  /// Kłus → galop.
  final double trotGallop;

  /// true = z wysokości w kłębie, false = z masy (gdy brak wzrostu).
  final bool fromHeight;
  const GaitZones(this.restBelow, this.walkTrot, this.trotGallop, {this.fromHeight = false});

  /// Progi z wysokości w kłębie (liczba Froude’a), a bez niej z masy
  /// (Heglund 1974). Bez obu danych – wartości dla psa ok. 25 kg.
  factory GaitZones.forDog({double? heightCm, double? kg}) {
    if (heightCm != null && heightCm >= 15 && heightCm <= 110) {
      final h = heightCm / 100;
      final wt = math.sqrt(0.5 * _g * h), tg = math.sqrt(2.5 * _g * h);
      return GaitZones(math.min(activeSpeedMs, wt * 0.8), wt, tg, fromHeight: true);
    }
    final m = (kg != null && kg > 0.5) ? kg.clamp(1.0, 100.0) : 25.0;
    final tg = 1.53 * math.pow(m, 0.24).toDouble();
    final wt = tg * math.sqrt(0.5 / 2.5);
    return GaitZones(math.min(activeSpeedMs, wt * 0.8), wt, tg);
  }

  PerfZone zoneOf(double speedMs) {
    if (speedMs < restBelow) return PerfZone.rest;
    if (speedMs < walkTrot) return PerfZone.low;
    if (speedMs < trotGallop) return PerfZone.moderate;
    return PerfZone.high;
  }
}

/// Jakość danych jednego treningu.
enum DataQuality {
  /// Pomiary gęste i ciągłe.
  good,

  /// Są luki albo rzadkie pomiary – wartości zaniżone lub przybliżone.
  partial,

  /// Za mało danych – statystyk psa nie pokazujemy.
  insufficient,

  /// Trening bez trackera na psie.
  none,
}

/// Skąd pochodzi szacunek kalorii.
enum KcalSource {
  /// Z trasy psa (tracker).
  dogGps,

  /// Z dystansu przewodnika (pies zwykle przebiega więcej – dolna granica).
  handlerDistance,

  /// Brak danych do szacunku (brak dystansu albo masy).
  none,
}

/// Szacowany wydatek energii na ruch (kcal).
class KcalEstimate {
  final double kcal;
  final KcalSource source;

  /// Czy wysiłek wykracza poza zwykłą dzienną aktywność (wliczoną w
  /// zapotrzebowanie podstawowe). Tylko taki doliczamy w bilansie.
  final bool extra;
  const KcalEstimate(this.kcal, this.source, {required this.extra});

  /// Orientacyjny zakres: indywidualne różnice i błąd GPS (±25%).
  double get low => kcal * 0.75;
  double get high => kcal * 1.25;

  static const none = KcalEstimate(0, KcalSource.none, extra: false);
}

/// Model wydatku energetycznego psa.
class DogEnergyModel {
  /// Spoczynkowe zapotrzebowanie (NRC 2006).
  static double rer(double kg) => Energy.rer(kg);

  /// Koszt netto ruchu (kcal) na [meters] przy masie [kg] (Taylor 1982).
  /// „Netto” = ponad spoczynek, więc nie dubluje się z RER.
  static double locomotionKcal(double kg, double meters) {
    if (kg <= 0 || meters <= 0) return 0;
    return kg * meters / 1000 * Energy.netRunKcalPerKgKm(kg);
  }

  /// Dyscypliny, w których wysiłek wykracza poza zwykły dzień psa – tak samo
  /// jak w module żywienia ([Energy.trainingKcal]), żeby bilans i dawka
  /// liczyły to samo. Spacer, IGP czy posłuszeństwo mieszczą się w mnożniku
  /// MER zapotrzebowania podstawowego.
  static bool isExtra(Discipline d) =>
      d == Discipline.canicross || d == Discipline.bikejoring || d == Discipline.condition;

  /// Szacunek dla treningu: z ruchu psa w strefach > odpoczynek (metry przebyte
  /// w odpoczynku to głównie szum GPS), a bez trackera – z dystansu
  /// przewodnika. Bez dystansu albo masy – brak szacunku.
  static KcalEstimate estimate({
    required Discipline discipline,
    required double? kg,
    double? dogActiveMeters,
    double? handlerMeters,
  }) {
    if (kg == null || kg <= 0) return KcalEstimate.none;
    final extra = isExtra(discipline);
    if (dogActiveMeters != null && dogActiveMeters > 0) {
      return KcalEstimate(locomotionKcal(kg, dogActiveMeters), KcalSource.dogGps, extra: extra);
    }
    if (handlerMeters != null && handlerMeters > 0 && discipline.hasDistance) {
      return KcalEstimate(locomotionKcal(kg, handlerMeters), KcalSource.handlerDistance, extra: extra);
    }
    return KcalEstimate.none;
  }
}

/// Wynik jednego treningu dla Valkor Performance.
class SessionMetrics {
  final TrainingSession session;

  /// Dystans psa (m) – null, gdy brak trackera albo za mało danych.
  final double? dogMeters;

  /// Dystans przewodnika (m): z trasy GPS telefonu albo wpisany ręcznie.
  final double? handlerMeters;

  /// Czas ruchu psa (s) – z trackera; bez niego z czasu ruchu treningu.
  final double? movingSec;

  /// Szacowany czas odpoczynku (s): odcinki z prędkością poniżej progu.
  /// Czas bez pomiarów nie jest wliczany ani do ruchu, ani do odpoczynku.
  final double? restSec;

  /// Czas bez pomiarów psa w trakcie treningu (s).
  final double? noDataSec;

  /// Średnia prędkość psa w ruchu i maksymalna (m/s).
  final double? avgSpeedMs, maxSpeedMs;

  /// Czas (s) i dystans (m) w strefach (indeks = [PerfZone.index]).
  final List<double> zoneSec;
  final List<double> zoneMeters;
  final DataQuality quality;

  /// Część treningu pokryta pomiarami psa (0–1).
  final double coverage;
  final double? medianIntervalSec;
  final List<DogStatsIssue> issues;

  /// Masa użyta do obliczeń (kg) – z historii masy z dnia treningu.
  final double? kg;
  final KcalEstimate kcal;

  /// Przewyższenia – zawsze null: trasa nie zapisuje wysokości, a wysokość
  /// z GPS (±10–20 m) nie nadaje się do sumowania podejść.
  double? get elevationGainM => null;

  const SessionMetrics({
    required this.session,
    this.dogMeters,
    this.handlerMeters,
    this.movingSec,
    this.restSec,
    this.noDataSec,
    this.avgSpeedMs,
    this.maxSpeedMs,
    this.zoneSec = const [0, 0, 0, 0],
    this.zoneMeters = const [0, 0, 0, 0],
    required this.quality,
    this.coverage = 0,
    this.medianIntervalSec,
    this.issues = const [],
    this.kg,
    this.kcal = KcalEstimate.none,
  });

  bool get hasDog => dogMeters != null;

  /// Obciążenie treningowe (sesyjne RPE × minuty, jak w zakładce Trening).
  double get load => session.load;

  double? get ratio =>
      dogMeters == null || handlerMeters == null || handlerMeters! < 50 ? null : dogMeters! / handlerMeters!;

  /// Oblicza wskaźniki treningu. [track] null = trening bez trasy GPS.
  static SessionMetrics of(TrainingSession s, Track? track, {double? kg, double? heightCm}) {
    double? handler = track != null && track.meters > 0 ? track.meters : null;
    if (handler == null && s.distanceKm != null && s.distanceKm! > 0) handler = s.distanceKm! * 1000;
    final sessionMoving = (s.movingSec ?? s.durationMin * 60).toDouble();

    if (track == null || !track.hasDog) {
      return SessionMetrics(
        session: s,
        handlerMeters: handler,
        movingSec: sessionMoving > 0 ? sessionMoving : null,
        quality: DataQuality.none,
        kg: kg,
        kcal: DogEnergyModel.estimate(discipline: s.discipline, kg: kg, handlerMeters: handler),
      );
    }

    final st = DogStats.of(track);
    final insufficient =
        st.issues.contains(DogStatsIssue.fewPoints) ||
        st.coverage < 0.3 ||
        (st.medianIntervalSec != null && st.medianIntervalSec! > 60);
    final quality = insufficient
        ? DataQuality.insufficient
        : st.issues.where((i) => i != DogStatsIssue.noHandler).isEmpty
        ? DataQuality.good
        : DataQuality.partial;
    if (quality == DataQuality.insufficient) {
      return SessionMetrics(
        session: s,
        handlerMeters: handler,
        movingSec: sessionMoving > 0 ? sessionMoving : null,
        quality: quality,
        coverage: st.coverage,
        medianIntervalSec: st.medianIntervalSec,
        issues: st.issues,
        kg: kg,
        kcal: DogEnergyModel.estimate(discipline: s.discipline, kg: kg, handlerMeters: handler),
      );
    }

    final zones = GaitZones.forDog(heightCm: heightCm, kg: kg);
    final zs = [0.0, 0.0, 0.0, 0.0], zm = [0.0, 0.0, 0.0, 0.0];
    double? maxV;
    for (final l in dogLegs(track)) {
      final dt = l.b.t - l.a.t;
      final z = zones.zoneOf(l.speedMs);
      zs[z.index] += dt;
      zm[z.index] += _d(l.a.ll, l.b.ll);
      // Maksimum tylko z odcinków ≥ 3 s – krótsze to głównie szum GPS.
      if (dt >= 3) maxV = math.max(maxV ?? 0, l.speedMs);
    }
    final moving = zs[1] + zs[2] + zs[3];
    final activeM = zm[1] + zm[2] + zm[3];
    final total = track.points.isEmpty ? 0.0 : track.points.last.t - track.points.first.t;
    final covered = zs.fold(0.0, (a, b) => a + b);
    return SessionMetrics(
      session: s,
      // Suma sprawdzonych odcinków: bez niemożliwych skoków i bez przerw > 2 min.
      dogMeters: zm.fold<double>(0, (a, b) => a + b),
      handlerMeters: handler,
      movingSec: moving,
      restSec: zs[0],
      noDataSec: math.max(0, total - covered),
      avgSpeedMs: moving > 0 ? activeM / moving : null,
      maxSpeedMs: maxV,
      zoneSec: zs,
      zoneMeters: zm,
      quality: quality,
      coverage: st.coverage,
      medianIntervalSec: st.medianIntervalSec,
      issues: st.issues,
      kg: kg,
      kcal: DogEnergyModel.estimate(discipline: s.discipline, kg: kg, dogActiveMeters: activeM, handlerMeters: handler),
    );
  }
}

/// Masa psa w dniu [d]: ostatni pomiar z tego dnia lub wcześniej, a gdy
/// takiego nie ma – najwcześniejszy późniejszy, w ostateczności masa z profilu.
double? weightOn(DateTime d, List<WeightEntry> weights, double? profileKg) {
  WeightEntry? before, after;
  final end = DateTime(d.year, d.month, d.day + 1);
  for (final w in weights) {
    if (w.kg <= 0) continue;
    if (w.date.isBefore(end)) {
      if (before == null || w.date.isAfter(before.date)) before = w;
    } else if (after == null || w.date.isBefore(after.date)) {
      after = w;
    }
  }
  return before?.kg ?? after?.kg ?? (profileKg != null && profileKg > 0 ? profileKg : null);
}

/// Usuwa podwójne wpisy tej samej aktywności: ten sam id, ta sama trasa albo
/// treningi nachodzące na siebie w czasie w ponad połowie (np. trening
/// wpisany ręcznie i ten sam nagrany GPS). Zostaje wpis z większą ilością danych.
/// Zwraca (unikalne, liczba pominiętych).
(List<TrainingSession>, int) dedupeSessions(Iterable<TrainingSession> input) {
  final byId = <String, TrainingSession>{};
  for (final t in input) {
    byId.putIfAbsent(t.id, () => t);
  }
  int richness(TrainingSession t) =>
      (t.hasTrack ? 4 : 0) + (t.distanceKm != null ? 2 : 0) + (t.movingSec != null ? 1 : 0);
  final list = byId.values.toList()
    ..sort((a, b) {
      final r = richness(b).compareTo(richness(a));
      return r != 0 ? r : a.date.compareTo(b.date);
    });
  final kept = <TrainingSession>[];
  final refs = <String>{};
  for (final t in list) {
    if (t.trackRef != null && !refs.add(t.trackRef!)) continue;
    final dup = kept.any((k) {
      final aS = t.date, aE = t.date.add(Duration(minutes: math.max(1, t.durationMin)));
      final bS = k.date, bE = k.date.add(Duration(minutes: math.max(1, k.durationMin)));
      final overlap = (aE.isBefore(bE) ? aE : bE).difference(aS.isAfter(bS) ? aS : bS).inSeconds;
      final shorter = math.min(aE.difference(aS).inSeconds, bE.difference(bS).inSeconds);
      return overlap > 0 && overlap > shorter / 2;
    });
    if (!dup) kept.add(t);
  }
  kept.sort((a, b) => a.date.compareTo(b.date));
  return (kept, input.length - kept.length);
}

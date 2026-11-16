import 'dart:math' as math;

import '../models.dart';
import 'nutrition_models.dart';

/// Obliczenia zapotrzebowania energetycznego psa.
///
/// Źródła wzorów: NRC 2006 „Nutrient Requirements of Dogs and Cats”,
/// WSAVA Global Nutrition Guidelines (RER = 70 × masa^0,75).
class Energy {
  /// Spoczynkowe zapotrzebowanie energetyczne (kcal/dzień).
  static double rer(double kg) => kg <= 0 ? 0 : 70 * math.pow(kg, 0.75).toDouble();

  /// Wiek w miesiącach (null, gdy brak daty urodzenia).
  static int? ageMonths(DateTime? birth, [DateTime? now]) {
    if (birth == null) return null;
    final n = now ?? DateTime.now();
    var m = (n.year - birth.year) * 12 + n.month - birth.month;
    if (n.day < birth.day) m--;
    return m < 0 ? 0 : m;
  }

  /// Mnożnik podstawowy wg wieku i kastracji (bez treningów – te liczymy osobno).
  static double lifeStageFactor(int? months, bool neutered) {
    if (months != null && months < 4) return 3.0;
    if (months != null && months < 12) return 2.0;
    if (months != null && months >= 96) return 1.4; // senior 8+ lat
    return neutered ? 1.6 : 1.8;
  }

  static String lifeStageLabel(int? months) {
    if (months == null) return 'dorosły';
    if (months < 4) return 'szczenię do 4 mies.';
    if (months < 12) return 'młody pies';
    if (months >= 96) return 'senior';
    return 'dorosły';
  }

  /// Dodatkowe kalorie spalone na treningu.
  ///
  /// Biegi z dystansem: koszt ruchu psa ok. 1,1 kcal na kg na km (spacer 0,8).
  /// Bez dystansu: wielokrotność spoczynkowego zużycia zależnie od intensywności (RPE).
  static double trainingKcal(TrainingSession t, double kg) {
    if (kg <= 0 || !t.done) return 0;
    final km = t.distanceKm ?? 0;
    if (t.discipline.hasDistance && km > 0) {
      final perKm = switch (t.discipline) {
        Discipline.walk => 0.8,
        Discipline.recovery => 0.7,
        _ => 1.1,
      };
      return kg * km * perKm;
    }
    final perMin = rer(kg) / 1440;
    final met = 1 + 0.5 * t.rpe.clamp(1, 10);
    final extra = t.discipline == Discipline.recovery ? 0.5 : (met - 1);
    return perMin * t.durationMin * extra;
  }
}

/// Wynik wyliczenia dziennej dawki.
class DailyPlan {
  final double weightKg;
  final double basisKg; // masa, od której liczymy (docelowa przy redukcji)
  final double rer;
  final double factor;
  final double baseKcal; // bez treningów
  final double trainingKcal;
  final double adjustPct;
  final double targetKcal; // łącznie na dziś
  final double eatenKcal;
  final double treatsKcal;
  final double supplementsKcal;
  final double mealsKcal;
  final double kcalPerGram; // karma główna
  final double dailyGrams; // całodzienna porcja karmy głównej (po odjęciu przysmaków)
  final double mealsGramsEaten;
  final double remainingGrams; // ile karmy zostało do podania dziś
  final double morningGrams;
  final double eveningGrams;
  final List<String> notes;

  const DailyPlan({
    required this.weightKg,
    required this.basisKg,
    required this.rer,
    required this.factor,
    required this.baseKcal,
    required this.trainingKcal,
    required this.adjustPct,
    required this.targetKcal,
    required this.eatenKcal,
    required this.treatsKcal,
    required this.supplementsKcal,
    required this.mealsKcal,
    required this.kcalPerGram,
    required this.dailyGrams,
    required this.mealsGramsEaten,
    required this.remainingGrams,
    required this.morningGrams,
    required this.eveningGrams,
    required this.notes,
  });

  double get remainingKcal => targetKcal - eatenKcal;
  double get balance => eatenKcal - targetKcal;
  double get treatsShare => targetKcal <= 0 ? 0 : treatsKcal / targetKcal;
}

/// Wylicza plan dnia. Funkcja czysta – łatwa do testowania.
DailyPlan computeDailyPlan({
  required Dog dog,
  required NutritionSettings settings,
  required List<TrainingSession> trainingsToday,
  required List<FeedingEntry> entriesToday,
  required double kcalPerGram,
  DateTime? now,
}) {
  final notes = <String>[];
  final weight = dog.weightKg ?? 0;
  final target = dog.targetWeightKg;
  final months = Energy.ageMonths(dog.birthDate, now);
  final growing = months != null && months < 12;

  var basis = weight;
  var factor = Energy.lifeStageFactor(months, settings.neutered) * settings.activity.factor;
  switch (settings.goal) {
    case NutritionGoal.lose:
      if (target != null && target > 0 && target < weight) basis = target;
      if (!growing) factor = 1.1 * settings.activity.factor; // ~1,1 × RER masy docelowej
      notes.add('Redukcja: liczę od masy docelowej${target != null ? ' (${target.toStringAsFixed(1)} kg)' : ''}.');
    case NutritionGoal.gain:
      factor *= 1.1;
      notes.add('Budowa masy: +10% do zapotrzebowania.');
    case NutritionGoal.maintain:
      break;
  }
  if (growing) notes.add('Młody pies ($months mies.): zapotrzebowanie wzrostowe.');

  final rer = Energy.rer(basis);
  final base = rer * factor;
  final training = trainingsToday.fold(0.0, (a, t) => a + Energy.trainingKcal(t, weight));
  final adj = settings.adjustPct;
  final targetKcal = (base + training) * (1 + adj / 100);

  var treats = 0.0, supp = 0.0, meals = 0.0, mealsGrams = 0.0;
  for (final e in entriesToday) {
    switch (e.kind) {
      case FeedKind.treat:
        treats += e.kcal;
      case FeedKind.supplement:
        supp += e.kcal;
      default:
        meals += e.kcal;
        mealsGrams += e.grams;
    }
  }
  final kpg = kcalPerGram <= 0 ? 3.7 : kcalPerGram;
  final dailyGrams = math.max(0.0, (targetKcal - treats - supp) / kpg);
  final remainingGrams = math.max(0.0, dailyGrams - mealsGrams);

  final morningDone = entriesToday.any((e) => e.kind == FeedKind.morning);
  final eveningDone = entriesToday.any((e) => e.kind == FeedKind.evening);
  double morning, evening;
  if (!morningDone && !eveningDone) {
    morning = remainingGrams * settings.morningShare;
    evening = remainingGrams - morning;
  } else if (morningDone && !eveningDone) {
    morning = entriesToday.where((e) => e.kind == FeedKind.morning).fold(0.0, (a, e) => a + e.grams);
    evening = remainingGrams;
  } else {
    morning = entriesToday.where((e) => e.kind == FeedKind.morning).fold(0.0, (a, e) => a + e.grams);
    evening = entriesToday.where((e) => e.kind == FeedKind.evening).fold(0.0, (a, e) => a + e.grams);
  }

  if (training > 0) notes.add('Treningi dziś: +${training.round()} kcal.');
  if (treats > 0) notes.add('Przysmaki: ${treats.round()} kcal odjęte od porcji karmy.');
  if (adj != 0) notes.add('Korekta z panelu AI: ${adj > 0 ? '+' : ''}${adj.round()}%.');

  return DailyPlan(
    weightKg: weight,
    basisKg: basis,
    rer: rer,
    factor: factor,
    baseKcal: base,
    trainingKcal: training,
    adjustPct: adj,
    targetKcal: targetKcal,
    eatenKcal: treats + supp + meals,
    treatsKcal: treats,
    supplementsKcal: supp,
    mealsKcal: meals,
    kcalPerGram: kpg,
    dailyGrams: dailyGrams,
    mealsGramsEaten: mealsGrams,
    remainingGrams: remainingGrams,
    morningGrams: morning,
    eveningGrams: evening,
    notes: notes,
  );
}

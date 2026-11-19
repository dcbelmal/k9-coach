import 'dart:math' as math;

import '../breeds/breed_info.dart';
import '../breeds/breed_sex.dart';
import '../breeds/breeds.dart' show canonicalBreedId;
import '../models.dart';
import 'nutrition_models.dart';
import '../l10n/l10n.dart';

/// Obliczenia zapotrzebowania energetycznego psa.
///
/// Źródła:
/// * NRC 2006 „Nutrient Requirements of Dogs and Cats” – RER = 70 × masa^0,75,
///   równanie wzrostu szczeniąt ME = 130 × BW^0,75 × 3,2 × (e^(−0,87·p) − 0,1),
///   gdzie p = masa obecna / spodziewana masa dorosła.
/// * WSAVA Global Nutrition Guidelines / AAHA 2021 Nutrition and Weight Management
///   Guidelines – orientacyjne mnożniki MER: dorosły niekastrowany 1,8,
///   kastrowany 1,6, mało aktywny 1,2–1,4, redukcja 1,0 × RER masy docelowej,
///   praca/sport 2,0–5,0. Indywidualne zapotrzebowanie psów o tej samej masie
///   różni się nawet o ±20–50%, dlatego wynik jest punktem startowym, który
///   koryguje się na podstawie masy ciała i BCS.
/// * Taylor i wsp. 1982 (J Exp Biol 97:1) – koszt netto biegu ssaków
///   10,7 × M^−0,316 J/(kg·m); dla psa 25 kg ≈ 0,92 kcal/kg/km.
/// * Laflamme 1997 – każdy punkt BCS powyżej 5/9 ≈ 10% nadmiaru masy.
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

  /// Masa (kg), od której pies uznawany jest za rasę dużą – rośnie dłużej.
  static const largeBreedKg = 25.0;

  /// Czy pies jeszcze rośnie. Małe i średnie rasy kończą wzrost ok. 12. miesiąca,
  /// duże i olbrzymie zwykle 15–24 mies. (AAHA 2021) – przyjmujemy 18.
  static bool isGrowing(int? months, {double? adultKg}) {
    if (months == null) return false;
    final limit = (adultKg ?? 0) >= largeBreedKg ? 18 : 12;
    return months < limit;
  }

  /// Wiek seniora zależy od wielkości psa (ostatnie ok. 25% życia, AAHA 2023):
  /// psy duże ok. 8 lat, pozostałe ok. 10 lat.
  static bool isSenior(int? months, {double? adultKg}) {
    if (months == null) return false;
    return months >= ((adultKg ?? 0) >= largeBreedKg ? 96 : 120);
  }

  /// Mnożnik MER psa dorosłego (bez zapisanych treningów, które liczymy osobno),
  /// wg tabel WSAVA/AAHA. Szczenięta – patrz [growthFactor].
  static double adultFactor(bool neutered, ActivityLevel activity) => switch (activity) {
        ActivityLevel.low => neutered ? 1.2 : 1.4,
        ActivityLevel.normal => neutered ? 1.6 : 1.8,
        ActivityLevel.high => 2.0,
      };

  /// Mnożnik dla rosnącego psa. Gdy znamy spodziewaną masę dorosłą – równanie
  /// NRC 2006 (wynik przeliczony na wielokrotność RER), w przeciwnym razie
  /// uproszczenie NRC/WSAVA: do 4 mies. 3,0 × RER, później 2,0 × RER.
  static double growthFactor(int months, double kg, double? adultKg) {
    if (adultKg != null && adultKg > 0 && kg > 0) {
      final p = (kg / adultKg).clamp(0.05, 1.0);
      final me = 130 * math.pow(kg, 0.75) * 3.2 * (math.exp(-0.87 * p) - 0.1);
      return (me / rer(kg)).clamp(1.6, 3.5).toDouble();
    }
    return months < 4 ? 3.0 : 2.0;
  }

  /// Uproszczony mnożnik (zgodność z wcześniejszymi wersjami i testami).
  static double lifeStageFactor(int? months, bool neutered) {
    if (months != null && months < 4) return 3.0;
    if (months != null && months < 12) return 2.0;
    return adultFactor(neutered, ActivityLevel.normal);
  }

  static String lifeStageLabel(int? months, {double? adultKg}) {
    if (months == null) return tr('dorosły');
    if (months < 4) return tr('szczenię do 4 mies.');
    if (isGrowing(months, adultKg: adultKg)) return tr('młody pies');
    if (isSenior(months, adultKg: adultKg)) return 'senior';
    return tr('dorosły');
  }

  /// Spodziewana masa dorosła z atlasu ras: środek zakresu dla płci psa,
  /// jeśli wzorzec go podaje, w przeciwnym razie środek zakresu ogólnego.
  static double? expectedAdultKg(Dog dog) {
    final i = breedInfoFor(dog.breedId);
    if (i == null || dog.mixed || i.weightMax <= 0) return null;
    final sex = breedSexDims[canonicalBreedId(dog.breedId)];
    final w = dog.female ? sex?.femaleWeight : sex?.maleWeight;
    if (w != null && w.max != null && w.max! > 0) return (w.min + w.max!) / 2;
    return (i.weightMin + i.weightMax) / 2;
  }

  /// Szacowana masa idealna z BCS (skala 1–9): ok. 10% nadmiaru na każdy punkt
  /// powyżej 5. Dla BCS ≤ 5 zwraca null (nie zgadujemy niedowagi).
  static double? idealFromBcs(double kg, int? bcs) {
    if (bcs == null || bcs <= 5 || kg <= 0) return null;
    return kg / (1 + 0.1 * (bcs.clamp(6, 9) - 5));
  }

  /// Koszt netto biegu (kcal na kg na km) wg Taylora i wsp. – mniejszy u dużych psów.
  static double netRunKcalPerKgKm(double kg) {
    if (kg <= 0) return 0;
    final jPerKgM = 10.7 * math.pow(kg, -0.316);
    return jPerKgM / 4.184; // kJ/(kg·km) → kcal/(kg·km)
  }

  /// Dyscypliny, w których zapisany dystans to bieg/ciągnięcie, a nie zwykły ruch.
  static bool _countsAsExtra(Discipline d) =>
      d == Discipline.canicross || d == Discipline.bikejoring || d == Discipline.condition;

  /// Dodatkowy wydatek energii z nietypowego wysiłku (kcal).
  ///
  /// Mnożnik MER obejmuje już zwykłą dzienną aktywność: spacery, krótkie
  /// sesje posłuszeństwa, nosework, IGP bez biegu. Doliczamy tylko koszt netto
  /// biegu z dystansem (canicross, bikejoring, kondycja), żeby nie liczyć
  /// tego samego ruchu dwa razy. Treningi bez dystansu nie zwiększają dawki.
  static double trainingKcal(TrainingSession t, double kg) {
    if (kg <= 0 || !t.done || !_countsAsExtra(t.discipline)) return 0;
    final km = t.distanceKm ?? 0;
    if (km <= 0) return 0;
    return kg * km.clamp(0, 200) * netRunKcalPerKgKm(kg);
  }
}

/// Wynik wyliczenia dziennej dawki.
class DailyPlan {
  final double weightKg;
  final double basisKg; // masa, od której liczymy (docelowa przy redukcji)
  final double rer;
  final double factor;
  final double baseKcal; // bazowe zapotrzebowanie (bez dodatkowego wysiłku)
  final double trainingKcal; // dodatkowy wydatek z nietypowego wysiłku
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

  /// Orientacyjny zakres zapotrzebowania (indywidualna zmienność ±20%).
  final double lowKcal;
  final double highKcal;

  /// Zapotrzebowanie na utrzymanie obecnej masy – do kontroli zbyt dużego ograniczenia.
  final double maintenanceKcal;

  /// Ograniczenie kalorii tak duże, że zwykła karma może nie pokryć składników niezbędnych.
  final bool restrictionWarning;

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
    this.lowKcal = 0,
    this.highKcal = 0,
    this.maintenanceKcal = 0,
    this.restrictionWarning = false,
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
  final months = Energy.ageMonths(dog.birthDate, now);
  final adultKg = Energy.expectedAdultKg(dog);
  final growing = Energy.isGrowing(months, adultKg: adultKg);
  final senior = Energy.isSenior(months, adultKg: adultKg);

  // Zapotrzebowanie na utrzymanie obecnej masy.
  final maintFactor = growing
      ? Energy.growthFactor(months!, weight, adultKg)
      : Energy.adultFactor(settings.neutered, settings.activity);
  final maintenance = Energy.rer(weight) * maintFactor;

  var basis = weight;
  var factor = maintFactor;
  if (growing) {
    notes.add(tr('Młody pies ({0} mies.): zapotrzebowanie wzrostowe.', [months]));
    if (settings.goal != NutritionGoal.maintain) {
      notes.add(tr('U rosnącego psa nie liczę redukcji ani budowy masy – zmianę dawki ustal z lekarzem weterynarii.'));
    }
  } else {
    switch (settings.goal) {
      case NutritionGoal.lose:
        final target = dog.targetWeightKg;
        final fromBcs = Energy.idealFromBcs(weight, dog.bcs);
        final ideal = (target != null && target > 0 && target < weight) ? target : fromBcs;
        if (ideal != null) {
          // Nie schodzimy poniżej 70% obecnej masy w jednym kroku – zbyt ambitny cel.
          basis = math.max(ideal, weight * 0.7);
          factor = 1.0; // WSAVA/AAHA: 1,0 × RER masy docelowej
          notes.add(tr('Redukcja: 1,0 × RER masy docelowej ({0} kg).', [basis.toStringAsFixed(1)]) +
              (ideal == fromBcs && ideal != target ? tr(' Masę docelową oszacowałem z BCS – wpisz ją w profilu.') : ''));
        } else {
          notes.add(tr('Redukcja: wpisz masę docelową w profilu (albo BCS), a policzę dawkę od masy idealnej.'));
        }
      case NutritionGoal.gain:
        final target = dog.targetWeightKg;
        if (target != null && target > weight) {
          basis = math.min(target, weight * 1.1);
          notes.add(tr('Budowa masy: liczę utrzymanie masy docelowej ({0} kg), stopniowo.', [basis.toStringAsFixed(1)]));
        } else {
          factor *= 1.1;
          notes.add(tr('Budowa masy: +10% do zapotrzebowania (wpisz masę docelową, by liczyć dokładniej).'));
        }
      case NutritionGoal.maintain:
        break;
    }
    if (senior) {
      notes.add(tr('Senior: zapotrzebowanie bywa niższe albo wyższe niż u dorosłego – kieruj się masą i BCS.'));
    }
  }

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

  if (training > 0) notes.add(tr('Bieg z dystansem dziś: +{0} kcal ponad zwykłą aktywność.', [training.round()]));
  if (treats > 0) notes.add(tr('Przysmaki: {0} kcal odjęte od porcji karmy.', [treats.round()]));
  if (adj != 0) notes.add(tr('Korekta zatwierdzona przez Ciebie: {0}{1}%.', [adj > 0 ? '+' : '', adj.round()]));

  // Karma główna pokrywa mniej niż ~80% energii utrzymania (np. silna redukcja albo
  // dużo przysmaków) – zwykła karma może nie dostarczyć wszystkich składników niezbędnych.
  final foodKcal = targetKcal - treats - supp;
  final restriction = maintenance > 0 && foodKcal < 0.8 * maintenance;
  if (restriction) {
    notes.add(tr('Karma główna da mniej niż 80% energii na utrzymanie. Przy takim ograniczeniu zwykła karma może nie pokryć białka, witamin i minerałów – rozważ karmę dietetyczną i skonsultuj plan z lekarzem weterynarii.'));
  }

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
    lowKcal: targetKcal * 0.8,
    highKcal: targetKcal * 1.2,
    maintenanceKcal: maintenance,
    restrictionWarning: restriction,
  );
}

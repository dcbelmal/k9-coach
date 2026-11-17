import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/nutrition/energy.dart';
import 'package:k9_coach/nutrition/label_parser.dart';
import 'package:k9_coach/nutrition/nutrition_models.dart';
import 'package:k9_coach/nutrition/product_lookup.dart';

void main() {
  final now = DateTime(2026, 11, 16, 12);
  Dog dog({double kg = 20, double? target, int ageMonths = 36}) => Dog(
        name: 'Test',
        weightKg: kg,
        targetWeightKg: target,
        birthDate: DateTime(now.year, now.month - ageMonths, 1),
      );

  test('RER 20 kg ≈ 662 kcal', () {
    expect(Energy.rer(20), closeTo(662, 1));
  });

  test('plan dorosłego psa bez treningów', () {
    final p = computeDailyPlan(
      dog: dog(),
      settings: NutritionSettings(),
      trainingsToday: [],
      entriesToday: [],
      kcalPerGram: 3.8,
      now: now,
    );
    expect(p.targetKcal, closeTo(662 * 1.8, 2));
    expect(p.dailyGrams, closeTo(662 * 1.8 / 3.8, 1));
    expect(p.morningGrams + p.eveningGrams, closeTo(p.dailyGrams, 0.01));
  });

  test('trening dodaje kalorie, przysmaki zmniejszają porcję', () {
    final t = TrainingSession(id: 't', discipline: Discipline.canicross, date: now, distanceKm: 5, durationMin: 30);
    final base = computeDailyPlan(
        dog: dog(), settings: NutritionSettings(), trainingsToday: [], entriesToday: [], kcalPerGram: 4, now: now);
    final withRun = computeDailyPlan(
        dog: dog(), settings: NutritionSettings(), trainingsToday: [t], entriesToday: [], kcalPerGram: 4, now: now);
    expect(withRun.trainingKcal, closeTo(20 * 5 * 1.1, 0.01));
    expect(withRun.targetKcal - base.targetKcal, closeTo(110, 0.5));

    final treats = [FeedingEntry(id: 'x', date: now, kind: FeedKind.treat, grams: 30, kcal: 100)];
    final withTreats = computeDailyPlan(
        dog: dog(), settings: NutritionSettings(), trainingsToday: [t], entriesToday: treats, kcalPerGram: 4, now: now);
    expect(withRun.dailyGrams - withTreats.dailyGrams, closeTo(25, 0.01)); // 100 kcal / 4 kcal/g
  });

  test('po porannym karmieniu wieczór dostaje resztę', () {
    final e = [FeedingEntry(id: 'm', date: now, kind: FeedKind.morning, grams: 100, kcal: 400)];
    final p = computeDailyPlan(
        dog: dog(), settings: NutritionSettings(), trainingsToday: [], entriesToday: e, kcalPerGram: 4, now: now);
    expect(p.morningGrams, 100);
    expect(p.eveningGrams, closeTo(p.dailyGrams - 100, 0.01));
  });

  test('redukcja liczy od masy docelowej', () {
    final p = computeDailyPlan(
        dog: dog(kg: 30, target: 25),
        settings: NutritionSettings(goal: NutritionGoal.lose),
        trainingsToday: [],
        entriesToday: [],
        kcalPerGram: 4,
        now: now);
    expect(p.basisKg, 25);
    expect(p.targetKcal, closeTo(Energy.rer(25) * 1.1, 1));
  });

  test('szczenię ma większe zapotrzebowanie', () {
    expect(Energy.lifeStageFactor(3, false), 3.0);
    expect(Energy.lifeStageFactor(8, false), 2.0);
    expect(Energy.lifeStageFactor(36, true), 1.6);
  });

  test('szacowanie kcal ze składu', () {
    final p = FoodProduct(id: '1', name: 'x', proteinPct: 26, fatPct: 16, fiberPct: 3, ashPct: 7, moisturePct: 9);
    // NFE = 39 → 3,5×26 + 8,5×16 + 3,5×39 = 363,5
    expect(p.estimatedKcalPer100g, closeTo(363.5, 0.01));
    expect(p.kcalPerGram, closeTo(3.635, 0.001));
  });

  test('ilość z opakowania', () {
    expect(ProductLookup.parseQuantity('12 kg'), 12000);
    expect(ProductLookup.parseQuantity('400g'), 400);
    expect(ProductLookup.parseQuantity('2 x 400 g'), 800);
    expect(ProductLookup.parseQuantity('1,5kg'), 1500);
    expect(ProductLookup.parseQuantity('brak'), null);
  });

  test('odczyt odpowiedzi Open Pet Food Facts', () {
    final p = ProductLookup.parse('5901234567890', {
      'status': 1,
      'product': {
        'product_name': 'Adult Large Breed',
        'brands': 'Brit, Brit Premium',
        'quantity': '15 kg',
        'categories_tags': ['en:dog-food', 'en:dry-dog-food'],
        'nutriments': {'energy-kcal_100g': 372, 'proteins_100g': 24, 'fat_100g': '14'},
        'ingredients_text': 'chicken, rice',
      }
    })!;
    expect(p.name, 'Adult Large Breed');
    expect(p.brand, 'Brit');
    expect(p.type, ProductType.dry);
    expect(p.kcalPer100g, 372);
    expect(p.fatPct, 14);
    expect(p.packageGrams, 15000);
    expect(ProductLookup.parse('1', {'status': 0}), null);
    expect(ProductLookup.guessType('en:dog-treats'), ProductType.treat);
  });

  test('zapis i odczyt JSON', () {
    final p = FoodProduct(id: '1', name: 'A', type: ProductType.treat, pieceGrams: 2, kcalPer100g: 300);
    final back = FoodProduct.fromJson(p.toJson());
    expect(back.kcalPerPiece, closeTo(6, 0.001));
    final s = NutritionSettings(goal: NutritionGoal.gain, adjustPct: -5);
    expect(NutritionSettings.fromJson(s.toJson()).goal, NutritionGoal.gain);
  });

  test('odczyt etykiety po polsku', () {
    const text = '''ADULT MEDIUM
Skład: mięso z kurczaka (26%), ryż, białko zwierzęce hydrolizowane 4%, tłuszcz drobiowy, burak.
Składniki analityczne: białko 25 %, zawartość tłuszczu 14,5%, włókno surowe 2,1%,
popiół surowy 6,8%, wilgotność 9%.
Energia metaboliczna: 3 890 kcal/kg
Masa netto 15 kg''';
    final v = LabelParser.parse(text);
    expect(v.protein, 25);
    expect(v.fat, 14.5);
    expect(v.fiber, 2.1);
    expect(v.ash, 6.8);
    expect(v.moisture, 9);
    expect(v.kcalPer100g, 389);
    expect(v.packageGrams, 15000);
    expect(v.composition, startsWith('Mięso z kurczaka'));
  });

  test('odczyt etykiety po angielsku z kcal/100 g', () {
    final v = LabelParser.parse(
        'Composition: chicken, rice. Analytical constituents: Protein 30%, Fat content 20%, Crude fibres 2.5%, '
        'Crude ash 7.5%, Moisture 10%. Energy: 395 kcal/100g');
    expect(v.protein, 30);
    expect(v.fat, 20);
    expect(v.fiber, 2.5);
    expect(v.kcalPer100g, 395);
  });

  test('UPCitemdb', () {
    final p = ProductLookup.parseUpc('3182550837866', {
      'code': 'OK',
      'items': [
        {'title': 'Royal Canin Medium Adult Dry Dog Food 15 kg', 'brand': 'Royal Canin', 'category': 'Dog Food'}
      ]
    })!;
    expect(p.brand, 'Royal Canin');
    expect(p.name, 'Medium Adult Dry Dog Food 15 kg');
    expect(p.packageGrams, 15000);
    expect(ProductLookup.parseUpc('1', {'items': []}), null);
  });
}

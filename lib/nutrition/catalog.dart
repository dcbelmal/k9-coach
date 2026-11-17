// ignore_for_file: unused_element_parameter
import '../models.dart' show newId;
import 'nutrition_models.dart';

/// Wbudowany katalog karm, których nie ma w darmowych bazach (Open Pet Food Facts itp.).
/// Działa bez internetu. Wartości z oficjalnych stron producentów – dodawaj tylko sprawdzone.
class _Entry {
  final List<String> codes;
  final String brand, name, composition;
  final ProductType type;
  final double? kcalPer100g, protein, fat, fiber, ash, moisture, packageGrams;
  const _Entry({
    required this.codes,
    required this.brand,
    required this.name,
    this.type = ProductType.dry,
    this.kcalPer100g,
    this.protein,
    this.fat,
    this.fiber,
    this.ash,
    this.moisture,
    this.packageGrams,
    this.composition = '',
  });
}

class FoodCatalog {
  static const _entries = [
    // royalcanin.com/pl (Sporting Life Energy 4800) – białko 32%, tłuszcz 30%, popiół 8,3%, włókno 2%,
    // 4522 kcal/kg – wartość z worka (podał Dawid).
    _Entry(
      codes: ['3182550837866'],
      brand: 'Royal Canin',
      name: 'Cyno Energy 4800',
      kcalPer100g: 452,
      protein: 32,
      fat: 30,
      fiber: 2,
      ash: 8.3,
      packageGrams: 20000,
      composition: 'Odwodnione białko drobiowe, tłuszcze zwierzęce, ryż, izolat białka roślinnego, '
          'hydrolizowane białka zwierzęce, wysłodki buraczane, włókna roślinne, olej rybny, składniki mineralne, '
          'łuski i nasiona babki płesznik, olej sojowy, ekstrakt z aksamitki (źródło luteiny), '
          'drożdże hydrolizowane, hydrolizowane skorupiaki (źródło glukozaminy), '
          'hydrolizowana chrząstka (źródło chondroityny).',
    ),
  ];

  static int get size => _entries.length;

  /// Produkt z katalogu po kodzie EAN albo null.
  static FoodProduct? byBarcode(String code) {
    final c = code.trim();
    for (final e in _entries) {
      if (e.codes.contains(c)) {
        return FoodProduct(
          id: newId(),
          name: e.name,
          brand: e.brand,
          type: e.type,
          barcode: c,
          kcalPer100g: e.kcalPer100g,
          proteinPct: e.protein,
          fatPct: e.fat,
          fiberPct: e.fiber,
          ashPct: e.ash,
          moisturePct: e.moisture,
          packageGrams: e.packageGrams,
          composition: e.composition,
          source: 'katalog',
        );
      }
    }
    return null;
  }
}

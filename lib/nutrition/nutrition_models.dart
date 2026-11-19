import 'package:material_ui/material_ui.dart';

import '../models.dart' show newId;
import '../l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Moduł Żywienie (AI Nutrition) – modele danych.
// Wszystko zapisuje się lokalnie (offline); format JSON jest gotowy do
// późniejszej synchronizacji z chmurą (pole updatedAt przy każdym rekordzie).
// ---------------------------------------------------------------------------

DateTime? _d(dynamic v) => v == null ? null : DateTime.parse(v as String);
double? _n(dynamic v) => (v as num?)?.toDouble();

enum ProductType {
  dry('Karma sucha', Icons.grain_rounded, Color(0xFFF5821F)),
  wet('Karma mokra', Icons.soup_kitchen_rounded, Color(0xFF30B0C7)),
  treat('Przysmak', Icons.cookie_rounded, Color(0xFFFFB020)),
  supplement('Suplement', Icons.medication_liquid_rounded, Color(0xFF34C759)),
  other('Inne', Icons.restaurant_rounded, Color(0xFF8E8E93));

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final Color color;
  const ProductType(this._label, this.icon, this.color);

  bool get isMainFood => this == dry || this == wet;
}

/// Produkt w lokalnej bazie (karma, przysmak, suplement).
class FoodProduct {
  final String id;
  String name;
  String brand;
  ProductType type;
  String barcode;
  double? kcalPer100g; // z etykiety
  double? proteinPct;
  double? fatPct;
  double? fiberPct;
  double? ashPct;
  double? moisturePct;
  double? packageGrams; // masa opakowania
  double? pieceGrams; // masa jednej sztuki (przysmaki, tabletki)
  String composition;
  String? photo; // FileStore
  String source; // manual / openpetfoodfacts / openfoodfacts
  bool favorite;
  DateTime updatedAt;

  FoodProduct({
    required this.id,
    required this.name,
    this.brand = '',
    this.type = ProductType.dry,
    this.barcode = '',
    this.kcalPer100g,
    this.proteinPct,
    this.fatPct,
    this.fiberPct,
    this.ashPct,
    this.moisturePct,
    this.packageGrams,
    this.pieceGrams,
    this.composition = '',
    this.photo,
    this.source = 'manual',
    this.favorite = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get title => brand.isEmpty ? name : '$brand $name';

  /// Kaloryczność z etykiety albo szacunek z analizy (zmodyfikowane współczynniki Atwatera, NRC 2006).
  double? get kcalPer100gEffective => kcalPer100g ?? estimatedKcalPer100g;
  bool get kcalEstimated => kcalPer100g == null && estimatedKcalPer100g != null;

  double? get estimatedKcalPer100g {
    final p = proteinPct, f = fatPct;
    if (p == null || f == null) return null;
    final moisture = moisturePct ?? (type == ProductType.wet ? 78 : 9);
    final ash = ashPct ?? (type == ProductType.wet ? 2.5 : 7);
    final fiber = fiberPct ?? (type == ProductType.wet ? 0.5 : 3);
    final nfe = (100 - p - f - moisture - ash - fiber).clamp(0, 100);
    return 3.5 * p + 8.5 * f + 3.5 * nfe;
  }

  double get kcalPerGram => (kcalPer100gEffective ?? defaultKcal(type)) / 100;

  /// Kalorie jednej sztuki (przysmak).
  double? get kcalPerPiece => pieceGrams == null ? null : pieceGrams! * kcalPerGram;

  static double defaultKcal(ProductType t) => switch (t) {
        ProductType.dry => 370,
        ProductType.wet => 100,
        ProductType.treat => 330,
        ProductType.supplement => 0,
        ProductType.other => 200,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'type': type.name,
        'barcode': barcode,
        'kcal': kcalPer100g,
        'protein': proteinPct,
        'fat': fatPct,
        'fiber': fiberPct,
        'ash': ashPct,
        'moisture': moisturePct,
        'pack': packageGrams,
        'piece': pieceGrams,
        'composition': composition,
        'photo': photo,
        'source': source,
        'fav': favorite,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FoodProduct.fromJson(Map<String, dynamic> j) => FoodProduct(
        id: j['id'],
        name: j['name'] ?? '',
        brand: j['brand'] ?? '',
        type: ProductType.values.asNameMap()[j['type']] ?? ProductType.other,
        barcode: j['barcode'] ?? '',
        kcalPer100g: _n(j['kcal']),
        proteinPct: _n(j['protein']),
        fatPct: _n(j['fat']),
        fiberPct: _n(j['fiber']),
        ashPct: _n(j['ash']),
        moisturePct: _n(j['moisture']),
        packageGrams: _n(j['pack']),
        pieceGrams: _n(j['piece']),
        composition: j['composition'] ?? '',
        photo: j['photo'],
        source: j['source'] ?? 'manual',
        favorite: j['fav'] ?? false,
        updatedAt: _d(j['updatedAt']),
      );
}

/// Otwarty worek / opakowanie w magazynie.
class FoodBag {
  final String id;
  String productId;
  DateTime opened;
  double initialGrams;
  double correctionGrams; // ręczna korekta (np. po zważeniu worka)
  DateTime? finished;
  double? price;
  DateTime updatedAt;

  FoodBag({
    required this.id,
    required this.productId,
    required this.opened,
    required this.initialGrams,
    this.correctionGrams = 0,
    this.finished,
    this.price,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get active => finished == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'product': productId,
        'opened': opened.toIso8601String(),
        'initial': initialGrams,
        'corr': correctionGrams,
        'finished': finished?.toIso8601String(),
        'price': price,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FoodBag.fromJson(Map<String, dynamic> j) => FoodBag(
        id: j['id'],
        productId: j['product'],
        opened: DateTime.parse(j['opened']),
        initialGrams: _n(j['initial']) ?? 0,
        correctionGrams: _n(j['corr']) ?? 0,
        finished: _d(j['finished']),
        price: _n(j['price']),
        updatedAt: _d(j['updatedAt']),
      );
}

enum FeedKind {
  morning('Poranne karmienie', Icons.wb_sunny_rounded, Color(0xFFFFC53D)),
  evening('Wieczorne karmienie', Icons.nights_stay_rounded, Color(0xFF5E8BFF)),
  extra('Dodatkowy posiłek', Icons.restaurant_rounded, Color(0xFFF5821F)),
  treat('Przysmak', Icons.cookie_rounded, Color(0xFFFFB020)),
  supplement('Suplement', Icons.medication_liquid_rounded, Color(0xFF34C759));

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  final Color color;
  const FeedKind(this._label, this.icon, this.color);

  bool get isMeal => this == morning || this == evening || this == extra;
}

/// Wpis w dzienniku żywienia.
class FeedingEntry {
  final String id;
  DateTime date;
  FeedKind kind;
  String? productId;
  String label; // nazwa, gdy produkt usunięto lub wpis bez produktu
  double grams;
  double? pieces;
  double kcal; // zapamiętane w chwili wpisu
  String? trainingId; // nagrody z treningu
  String notes;
  DateTime updatedAt;

  FeedingEntry({
    required this.id,
    required this.date,
    required this.kind,
    this.productId,
    this.label = '',
    this.grams = 0,
    this.pieces,
    this.kcal = 0,
    this.trainingId,
    this.notes = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Ten sam wpis z innym ID (np. stałym, żeby ponowienie zapisu nie dublowało wpisu).
  FeedingEntry copyWithId(String newId) => FeedingEntry(
        id: newId,
        date: date,
        kind: kind,
        productId: productId,
        label: label,
        grams: grams,
        pieces: pieces,
        kcal: kcal,
        trainingId: trainingId,
        notes: notes,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'product': productId,
        'label': label,
        'g': grams,
        'pcs': pieces,
        'kcal': kcal,
        'training': trainingId,
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FeedingEntry.fromJson(Map<String, dynamic> j) => FeedingEntry(
        id: j['id'],
        date: DateTime.parse(j['date']),
        kind: FeedKind.values.asNameMap()[j['kind']] ?? FeedKind.extra,
        productId: j['product'],
        label: j['label'] ?? '',
        grams: _n(j['g']) ?? 0,
        pieces: _n(j['pcs']),
        kcal: _n(j['kcal']) ?? 0,
        trainingId: j['training'],
        notes: j['notes'] ?? '',
        updatedAt: _d(j['updatedAt']),
      );
}

/// Stały harmonogram suplementu (codzienne przypomnienie).
class SupplementPlan {
  final String id;
  String name;
  String dose;
  String? productId;
  int hour;
  int minute;
  bool active;

  SupplementPlan({
    required this.id,
    required this.name,
    this.dose = '',
    this.productId,
    this.hour = 8,
    this.minute = 0,
    this.active = true,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'dose': dose, 'product': productId, 'h': hour, 'm': minute, 'active': active};

  factory SupplementPlan.fromJson(Map<String, dynamic> j) => SupplementPlan(
        id: j['id'] ?? newId(),
        name: j['name'] ?? '',
        dose: j['dose'] ?? '',
        productId: j['product'],
        hour: j['h'] ?? 8,
        minute: j['m'] ?? 0,
        active: j['active'] ?? true,
      );
}

enum NutritionGoal {
  maintain('Utrzymanie wagi', Icons.balance_rounded),
  lose('Redukcja', Icons.trending_down_rounded),
  gain('Budowa masy', Icons.trending_up_rounded);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  const NutritionGoal(this._label, this.icon);
}

enum ActivityLevel {
  low('Spokojny', 'Mało ruchu poza treningami', 0.85),
  normal('Umiarkowany', 'Codzienne spacery, zwykła aktywność', 1.0),
  high('Bardzo aktywny', 'Dużo swobodnego biegania lub codzienna praca (poza zapisanymi treningami)', 1.2);

  final String _label;
  String get label => tr(_label);
  final String _hint;
  String get hint => tr(_hint);
  /// Dawny mnożnik aktywności (nieużywany w obliczeniach od 0.15 – patrz Energy.adultFactor).
  final double factor;
  const ActivityLevel(this._label, this._hint, this.factor);
}

/// Ustawienia żywienia psa.
class NutritionSettings {
  NutritionGoal goal;
  ActivityLevel activity;
  bool neutered;
  String? mainProductId;
  double morningShare; // część dziennej porcji rano (0..1)
  int morningHour, morningMinute, eveningHour, eveningMinute;
  bool feedReminders;
  bool stockReminders;
  int buyLeadDays; // ile dni przed końcem worka przypomnieć o zakupie
  double adjustPct; // korekta dawki zaakceptowana z panelu AI (np. -10)
  DateTime updatedAt;

  NutritionSettings({
    this.goal = NutritionGoal.maintain,
    this.activity = ActivityLevel.normal,
    this.neutered = false,
    this.mainProductId,
    this.morningShare = 0.5,
    this.morningHour = 7,
    this.morningMinute = 0,
    this.eveningHour = 18,
    this.eveningMinute = 0,
    this.feedReminders = true,
    this.stockReminders = true,
    this.buyLeadDays = 5,
    this.adjustPct = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        'activity': activity.name,
        'neutered': neutered,
        'main': mainProductId,
        'mShare': morningShare,
        'mh': morningHour,
        'mm': morningMinute,
        'eh': eveningHour,
        'em': eveningMinute,
        'feedRem': feedReminders,
        'stockRem': stockReminders,
        'lead': buyLeadDays,
        'adjust': adjustPct,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory NutritionSettings.fromJson(Map<String, dynamic> j) => NutritionSettings(
        goal: NutritionGoal.values.asNameMap()[j['goal']] ?? NutritionGoal.maintain,
        activity: ActivityLevel.values.asNameMap()[j['activity']] ?? ActivityLevel.normal,
        neutered: j['neutered'] ?? false,
        mainProductId: j['main'],
        morningShare: _n(j['mShare']) ?? 0.5,
        morningHour: j['mh'] ?? 7,
        morningMinute: j['mm'] ?? 0,
        eveningHour: j['eh'] ?? 18,
        eveningMinute: j['em'] ?? 0,
        feedReminders: j['feedRem'] ?? true,
        stockReminders: j['stockRem'] ?? true,
        buyLeadDays: j['lead'] ?? 5,
        adjustPct: _n(j['adjust']) ?? 0,
        updatedAt: _d(j['updatedAt']),
      );
}

/// Zapis zmiany dawki (historia zmian).
class DoseChange {
  final DateTime date;
  final double fromGrams;
  final double toGrams;
  final double kcal;
  final String reason;
  const DoseChange(this.date, this.fromGrams, this.toGrams, this.kcal, this.reason);

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'from': fromGrams, 'to': toGrams, 'kcal': kcal, 'reason': reason};
  factory DoseChange.fromJson(Map<String, dynamic> j) => DoseChange(DateTime.parse(j['date']), _n(j['from']) ?? 0,
      _n(j['to']) ?? 0, _n(j['kcal']) ?? 0, j['reason'] ?? '');
}

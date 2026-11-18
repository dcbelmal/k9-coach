import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../storage/dog_doc_guard.dart';
import '../storage/safe_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';

import '../files/file_store.dart';
import '../models.dart';
import '../notifications.dart';
import '../store.dart';
import 'energy.dart';
import 'nutrition_models.dart';
import '../l10n/l10n.dart';

/// Prognoza zużycia worka karmy.
class StockForecast {
  final FoodBag bag;
  final FoodProduct? product;
  final double remainingGrams;
  final double dailyUse; // g/dzień
  final DateTime? emptyDate;
  final DateTime? buyDate;
  const StockForecast(this.bag, this.product, this.remainingGrams, this.dailyUse, this.emptyDate, this.buyDate);

  double get fraction => bag.initialGrams <= 0 ? 0 : (remainingGrams / bag.initialGrams).clamp(0, 1).toDouble();
  int? get daysLeft => dailyUse <= 0 ? null : (remainingGrams / dailyUse).floor();
}

/// Dane jednego dnia (do wykresów).
class DayStats {
  final DateTime day;
  final double kcal;
  final double mealGrams;
  final double treatKcal;
  final double treatPieces;
  final double targetKcal;
  const DayStats(this.day, this.kcal, this.mealGrams, this.treatKcal, this.treatPieces, this.targetKcal);
}

/// Stan modułu Żywienie. Osobny klucz w pamięci telefonu, więc nie wpływa
/// na zapis pozostałych danych aplikacji.
class NutritionStore extends ChangeNotifier {
  NutritionStore._();
  static final NutritionStore instance = NutritionStore._();

  static const _key = 'k9coach_nutrition_v1';
  SharedPreferences? _prefs;

  List<FoodProduct> products = [];
  List<FoodBag> bags = [];
  List<FeedingEntry> entries = [];
  List<SupplementPlan> supplements = [];
  List<DoseChange> doseHistory = [];
  Map<String, double> targetByDay = {}; // yyyy-mm-dd -> kcal (dla wykresów)
  NutritionSettings settings = NutritionSettings();
  DateTime? lastSync;

  AppStore get app => AppStore.instance;

  final guard = DogDocGuard(_key, 'Żywienie');

  /// Wpisy, których nie udało się odczytać (wracają do zapisu bez zmian).
  Map<String, List<dynamic>> _bad = {};

  /// Dziennik: treningi z nagrodami, których zapis w historii nie został potwierdzony.
  Map<String, Map<String, dynamic>> _pendingTrainings = {};
  Map<String, dynamic> _extra = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    // Każda zmiana psa lub treningów przelicza dzisiejszą dawkę.
    if (!_listening) {
      _listening = true;
      app.addListener(() {
        _planCache = null;
        notifyListeners();
      });
    }
    _planCache = null;
    var x = _NutState.parse(null);
    await guard.load(_prefs!, DogProfiles.instance.activeId, (raw) => x = _NutState.parse(raw));
    _apply(x);
    notifyListeners();
    await _completePending();
  }

  bool _listening = false;

  void _apply(_NutState x) {
    products = x.products;
    bags = x.bags;
    entries = x.entries;
    supplements = x.supplements;
    doseHistory = x.doses;
    targetByDay = x.targets;
    settings = x.settings;
    lastSync = x.lastSync;
    _bad = x.bad;
    _pendingTrainings = x.pending;
    _extra = x.extra;
  }

  Map<String, dynamic> toJson() {
    List<dynamic> sec(String name, List<dynamic> items) => [for (final e in items) e.toJson(), ...?_bad[name]];
    return {
      ..._extra,
      'version': 1,
      'products': sec('products', products),
      'bags': sec('bags', bags),
      'entries': sec('entries', entries),
      'supplements': sec('supplements', supplements),
      'doses': sec('doses', doseHistory),
      'targets': targetByDay,
      'settings': settings.toJson(),
      'lastSync': lastSync?.toIso8601String(),
      if (_pendingTrainings.isNotEmpty) 'pendingTrainings': _pendingTrainings,
    };
  }

  Future<void> _save({bool reschedule = true}) async {
    entries.sort((a, b) => b.date.compareTo(a.date));
    products.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _planCache = null;
    _prefs ??= await SharedPreferences.getInstance();
    try {
      await guard.write(_prefs!, () => jsonEncode(toJson()), (last) => _apply(_NutState.parse(last)));
    } finally {
      _planCache = null;
      notifyListeners();
    }
    if (reschedule) await Notifications.instance.reschedule(app);
  }

  /// Dokańcza zapis treningów z nagrodami przerwany przed potwierdzeniem w historii.
  Future<void> _completePending() async {
    if (_pendingTrainings.isEmpty || guard.locked) return;
    for (final e in _pendingTrainings.entries.toList()) {
      try {
        final t = TrainingSession.fromJson(Map<String, dynamic>.from(e.value['training'] as Map));
        await app.upsertTrainingFor(e.value['dog'] as String? ?? guard.owner, t);
        _pendingTrainings.remove(e.key);
      } catch (err) {
        logError('Żywienie: dokończenie treningu', err);
      }
    }
    try {
      await _save(reschedule: false);
    } catch (err) {
      logError('Żywienie: zapis dziennika', err);
    }
  }

  // --- Produkty ------------------------------------------------------------

  FoodProduct? product(String? id) {
    if (id == null) return null;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  FoodProduct? byBarcode(String code) {
    final c = code.trim();
    if (c.isEmpty) return null;
    for (final p in products) {
      if (p.barcode == c) return p;
    }
    return null;
  }

  List<FoodProduct> ofType(Set<ProductType> types) =>
      products.where((p) => types.contains(p.type)).toList()
        ..sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));

  Future<void> upsertProduct(FoodProduct p) async {
    p.updatedAt = DateTime.now();
    products.removeWhere((e) => e.id == p.id);
    products.add(p);
    if (settings.mainProductId == null && p.type.isMainFood) settings.mainProductId = p.id;
    await _save();
  }

  Future<void> deleteProduct(FoodProduct p) async {
    products.removeWhere((e) => e.id == p.id);
    bags.removeWhere((b) => b.productId == p.id && b.active);
    if (settings.mainProductId == p.id) settings.mainProductId = null;
    await _save();
    if (p.photo != null) await FileStore.deleteIfUnreferenced(p.photo!);
  }

  // --- Główna karma i magazyn ----------------------------------------------

  /// Karma główna: z ustawień, albo z ostatnio otwartego worka.
  FoodProduct? get mainProduct {
    final p = product(settings.mainProductId);
    if (p != null) return p;
    final open = activeBags;
    if (open.isNotEmpty) return product(open.first.productId);
    final foods = products.where((p) => p.type.isMainFood);
    return foods.isEmpty ? null : foods.first;
  }

  List<FoodBag> get activeBags => bags.where((b) => b.active).toList()..sort((a, b) => b.opened.compareTo(a.opened));

  FoodBag? activeBagFor(String productId) {
    for (final b in activeBags) {
      if (b.productId == productId) return b;
    }
    return null;
  }

  double usedFromBag(FoodBag b) => entries
      .where((e) => e.productId == b.productId && !e.date.isBefore(b.opened) && (b.finished == null || e.date.isBefore(b.finished!)))
      .fold(0.0, (a, e) => a + e.grams);

  double remainingIn(FoodBag b) => math.max(0, b.initialGrams - usedFromBag(b) + b.correctionGrams);

  /// Średnie dzienne zużycie produktu z ostatnich 14 dni (lub plan dawki).
  double dailyUse(String productId) {
    final now = DateTime.now();
    final from = dayOnly(now).subtract(const Duration(days: 14));
    final list = entries.where((e) => e.productId == productId && !e.date.isBefore(from)).toList();
    if (list.isNotEmpty) {
      final first = list.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
      final days = math.max(1, dayOnly(now).difference(dayOnly(first)).inDays + 1);
      final total = list.fold(0.0, (a, e) => a + e.grams);
      if (days >= 3 || list.length >= 4) return total / days;
    }
    if (mainProduct?.id == productId) return plan?.dailyGrams ?? 0;
    return 0;
  }

  StockForecast forecast(FoodBag b) {
    final rem = remainingIn(b);
    final use = dailyUse(b.productId);
    DateTime? empty, buy;
    if (use > 0) {
      empty = dayOnly(DateTime.now()).add(Duration(days: (rem / use).floor()));
      buy = empty.subtract(Duration(days: settings.buyLeadDays));
    }
    return StockForecast(b, product(b.productId), rem, use, empty, buy);
  }

  StockForecast? get mainForecast {
    final m = mainProduct;
    if (m == null) return null;
    final b = activeBagFor(m.id);
    return b == null ? null : forecast(b);
  }

  Future<void> openBag(FoodBag b, {bool finishPrevious = true}) async {
    if (finishPrevious) {
      for (final o in bags.where((x) => x.active && x.productId == b.productId && x.id != b.id)) {
        o.finished = b.opened;
        o.updatedAt = DateTime.now();
      }
    }
    bags.removeWhere((x) => x.id == b.id);
    bags.add(b);
    await _save();
  }

  Future<void> upsertBag(FoodBag b) async {
    b.updatedAt = DateTime.now();
    bags.removeWhere((x) => x.id == b.id);
    bags.add(b);
    await _save();
  }

  Future<void> finishBag(FoodBag b) async {
    b.finished = DateTime.now();
    b.updatedAt = DateTime.now();
    await _save();
  }

  /// Ustawia faktyczną ilość karmy w worku (po zważeniu).
  Future<void> setRemaining(FoodBag b, double grams) async {
    b.correctionGrams = grams - (b.initialGrams - usedFromBag(b));
    b.updatedAt = DateTime.now();
    await _save();
  }

  Future<void> deleteBag(FoodBag b) async {
    bags.removeWhere((x) => x.id == b.id);
    await _save();
  }

  // --- Dziennik --------------------------------------------------------------

  List<FeedingEntry> entriesOn(DateTime day) => entries.where((e) => sameDay(e.date, day)).toList();

  Future<void> addEntry(FeedingEntry e) async => upsertEntries([e]);

  Future<void> upsertEntries(List<FeedingEntry> list) async {
    final ids = list.map((e) => e.id).toSet();
    entries.removeWhere((x) => ids.contains(x.id));
    for (final e in list) {
      e.updatedAt = DateTime.now();
      entries.add(e);
    }
    await _save();
  }

  Future<void> deleteEntry(FeedingEntry e) async {
    entries.removeWhere((x) => x.id == e.id);
    await _save();
  }

  /// Wpis z produktu: liczy kalorie z gramów albo sztuk.
  FeedingEntry entryFor(FoodProduct? p, FeedKind kind, {double grams = 0, double? pieces, DateTime? date, String? trainingId}) {
    var g = grams;
    if (pieces != null && p?.pieceGrams != null) g = pieces * p!.pieceGrams!;
    final kcal = p == null ? 0.0 : g * p.kcalPerGram;
    return FeedingEntry(
      id: newId(),
      date: date ?? DateTime.now(),
      kind: kind,
      productId: p?.id,
      label: p?.title ?? kind.label,
      grams: g,
      pieces: pieces,
      kcal: kcal,
      trainingId: trainingId,
    );
  }

  // --- Suplementy --------------------------------------------------------------

  Future<void> upsertSupplement(SupplementPlan s) async {
    supplements.removeWhere((x) => x.id == s.id);
    supplements.add(s);
    await _save();
  }

  Future<void> deleteSupplement(SupplementPlan s) async {
    supplements.removeWhere((x) => x.id == s.id);
    await _save();
  }

  // --- Ustawienia ----------------------------------------------------------

  Future<void> saveSettings(NutritionSettings s, {String reason = 'Zmiana ustawień'}) async {
    final before = plan?.dailyGrams;
    s.updatedAt = DateTime.now();
    settings = s;
    _planCache = null;
    final after = plan?.dailyGrams;
    if (before != null && after != null) _logDose(before, after, reason);
    await _save();
  }

  void _logDose(double from, double to, String reason) {
    if (from <= 0 || (to - from).abs() / from < 0.03) return;
    doseHistory.insert(0, DoseChange(DateTime.now(), from, to, plan?.targetKcal ?? 0, reason));
    if (doseHistory.length > 200) doseHistory.removeLast();
    Notifications.instance.showNow(
      Notifications.doseChangeId,
      tr('Zmiana dawki karmy'),
      tr('{0}: {1} g → {2} g na dzień ({3})', [app.dog?.name ?? trc('dog', 'Pies'), from.round(), to.round(), reason]),
    );
  }

  // --- Plan dnia -------------------------------------------------------------

  DailyPlan? _planCache;
  String _planKey = '';

  /// Dzisiejszy plan (pamiętany do zmiany danych, żeby nie liczyć przy każdym odświeżeniu).
  DailyPlan? get plan {
    final dog = app.dog;
    if (dog == null || (dog.weightKg ?? 0) <= 0) return null;
    final today = dayOnly(DateTime.now());
    final key = '${today.toIso8601String()}|${app.trainings.length}|${dog.weightKg}|${dog.targetWeightKg}|${entries.length}';
    if (_planCache != null && _planKey == key) return _planCache;
    _planKey = key;
    _planCache = planFor(today);
    return _planCache;
  }

  DailyPlan? planFor(DateTime day) {
    final dog = app.dog;
    if (dog == null || (dog.weightKg ?? 0) <= 0) return null;
    return computeDailyPlan(
      dog: dog,
      settings: settings,
      trainingsToday: app.doneTrainings.where((t) => sameDay(t.date, day)).toList(),
      entriesToday: entriesOn(day),
      kcalPerGram: mainProduct?.kcalPerGram ?? 3.7,
      now: day,
    );
  }

  /// Zapamiętuje cel kalorii dnia i loguje zmianę dawki po nowym treningu itp.
  void recordToday() {
    final p = plan;
    if (p == null) return;
    final k = dayOnly(DateTime.now()).toIso8601String().substring(0, 10);
    final old = targetByDay[k];
    if (old != null && (old - p.targetKcal).abs() < 1) return;
    targetByDay[k] = p.targetKcal;
    if (targetByDay.length > 400) {
      final keys = targetByDay.keys.toList()..sort();
      for (final x in keys.take(targetByDay.length - 400)) {
        targetByDay.remove(x);
      }
    }
    _save(reschedule: false).catchError((Object e) => logError('Żywienie: cel dnia', e));
  }

  /// Statystyki dzień po dniu (najstarszy pierwszy).
  List<DayStats> lastDays(int n) {
    final today = dayOnly(DateTime.now());
    final res = <DayStats>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final list = entriesOn(d);
      double kcal = 0, grams = 0, tk = 0, tp = 0;
      for (final e in list) {
        kcal += e.kcal;
        if (e.kind.isMeal) grams += e.grams;
        if (e.kind == FeedKind.treat) {
          tk += e.kcal;
          tp += e.pieces ?? 1;
        }
      }
      final t = targetByDay[d.toIso8601String().substring(0, 10)] ?? (i == 0 ? plan : planFor(d))?.targetKcal ?? 0;
      res.add(DayStats(d, kcal, grams, tk, tp, t));
    }
    return res;
  }

  // --- Nagrody w treningu ---------------------------------------------------

  /// Zapisuje trening oraz zużyte nagrody (zmniejszają porcję karmy).
  ///
  /// Odporne na przerwanie i ponowienie:
  /// 1. jeden zapis żywienia: nagrody ze stałymi ID (`treat_<trening>_<produkt>`)
  ///    oraz wpis w dzienniku z treścią treningu,
  /// 2. zapis treningu w historii psa (upsert po ID – bez duplikatów),
  /// 3. usunięcie wpisu z dziennika. Po restarcie krok 2 dokańcza [load].
  Future<DailyPlan?> saveTrainingWithTreats(TrainingSession t, Map<String, double> piecesByProduct,
      {String? dogId}) {
    final owner = dogId ?? DogProfiles.instance.activeId;
    return DogProfiles.instance.track(() async {
      final before = plan?.dailyGrams;
      final existed = app.hasTrainingFor(owner, t.id);
      final list = <FeedingEntry>[];
      piecesByProduct.forEach((pid, pcs) {
        if (pcs <= 0) return;
        final p = product(pid);
        final e = p?.pieceGrams == null
            ? entryFor(p, FeedKind.treat, grams: pcs, date: t.date, trainingId: t.id)
            : entryFor(p, FeedKind.treat, pieces: pcs, date: t.date, trainingId: t.id);
        list.add(e.copyWithId('treat_${t.id}_$pid'));
      });
      entries.removeWhere((e) => e.trainingId == t.id);
      entries.addAll(list);
      _pendingTrainings[t.id] = {'dog': owner, 'training': t.toJson()};
      await _save(reschedule: false);
      await app.upsertTrainingFor(owner, t);
      _pendingTrainings.remove(t.id);
      final after = plan?.dailyGrams;
      if (!existed && before != null && after != null) {
        _logDose(before, after, tr('trening {0}', [t.discipline.label]));
      }
      await _save(reschedule: false);
      return plan;
    });
  }

  List<FeedingEntry> treatsForTraining(String trainingId) =>
      entries.where((e) => e.trainingId == trainingId).toList();

  // --- Powiadomienia ---------------------------------------------------------

  /// Jednorazowe przypomnienia modułu (dołączane do wspólnego planu).
  List<(DateTime, String, String)> notificationPlan() {
    final out = <(DateTime, String, String)>[];
    if (!settings.stockReminders) return out;
    final name = app.dog?.name ?? trc('dog', 'Pies');
    for (final b in activeBags) {
      final f = forecast(b);
      if (f.emptyDate == null || f.product == null) continue;
      final buy = f.buyDate!;
      out.add((DateTime(buy.year, buy.month, buy.day, 10), tr('Czas kupić nowy worek'),
          tr('{0}: {1} skończy się ok. {2}.{3}', [name, f.product!.title, f.emptyDate!.day, f.emptyDate!.month.toString().padLeft(2, '0')])));
      final e = f.emptyDate!.subtract(const Duration(days: 1));
      out.add((DateTime(e.year, e.month, e.day, 19), tr('Kończy się karma'),
          tr('{0}: w worku zostało na ok. 1 dzień ({1})', [name, f.product!.title])));
    }
    return out;
  }

  /// Codzienne, powtarzalne przypomnienia (godzina, tytuł, treść).
  List<(int, int, String, String)> dailyReminders() {
    final out = <(int, int, String, String)>[];
    final name = app.dog?.name ?? trc('dog', 'Pies');
    final p = plan;
    final food = mainProduct?.title ?? tr('karma');
    if (settings.feedReminders) {
      final total = p?.dailyGrams ?? 0;
      final m = total * settings.morningShare, e = total - m;
      out.add((settings.morningHour, settings.morningMinute, tr('Poranne karmienie'),
          total > 0 ? tr('{0}: ok. {1} g ({2})', [name, m.round(), food]) : tr('Pora nakarmić psa: {0}', [name])));
      out.add((settings.eveningHour, settings.eveningMinute, tr('Wieczorne karmienie'),
          total > 0 ? tr('{0}: ok. {1} g, sprawdź porcję po przysmakach', [name, e.round()]) : tr('Pora nakarmić psa: {0}', [name])));
    }
    for (final s in supplements.where((s) => s.active).take(6)) {
      out.add((s.hour, s.minute, tr('Suplement: {0}', [s.name]), '$name${s.dose.isEmpty ? '' : ' – ${s.dose}'}'));
    }
    return out;
  }

  // --- Dane przykładowe ----------------------------------------------------

  Future<void> loadDemo() async {
    final now = DateTime.now();
    final today = dayOnly(now);
    products = [
      FoodProduct(
          id: 'np1',
          name: tr('Sport 30/20'),
          brand: tr('Brit Premium'),
          type: ProductType.dry,
          kcalPer100g: 395,
          proteinPct: 30,
          fatPct: 20,
          fiberPct: 2.5,
          ashPct: 7.5,
          moisturePct: 10,
          packageGrams: 12000,
          composition: tr('Kurczak (40%), ryż, tłuszcz drobiowy, łosoś, drożdże, olej z łososia…'),
          favorite: true),
      FoodProduct(
          id: 'np2',
          name: tr('Jagnięcina z ryżem (puszka)'),
          brand: tr('Rocco'),
          type: ProductType.wet,
          kcalPer100g: 110,
          proteinPct: 10,
          fatPct: 7,
          moisturePct: 78,
          packageGrams: 400),
      FoodProduct(
          id: 'np3',
          name: tr('Kostki treningowe wołowe'),
          brand: tr('Trainer'),
          type: ProductType.treat,
          kcalPer100g: 340,
          pieceGrams: 1.5,
          packageGrams: 200,
          favorite: true),
      FoodProduct(id: 'np4', name: tr('Suszona wątróbka'), brand: '', type: ProductType.treat, kcalPer100g: 380, pieceGrams: 2),
      FoodProduct(
          id: 'np5', name: tr('Antiflexi'), brand: tr('Biofaktor'), type: ProductType.supplement, kcalPer100g: 250, pieceGrams: 2),
    ];
    settings = NutritionSettings(mainProductId: 'np1', goal: NutritionGoal.gain, activity: ActivityLevel.high);
    bags = [
      FoodBag(id: 'nb1', productId: 'np1', opened: today.subtract(const Duration(days: 18)), initialGrams: 12000, price: 239),
    ];
    entries = [];
    final rnd = math.Random(3);
    for (var d = 18; d >= 1; d--) {
      final day = today.subtract(Duration(days: d));
      final m = 150 + rnd.nextInt(20).toDouble(), e = 160 + rnd.nextInt(30).toDouble();
      entries.add(FeedingEntry(
          id: 'nm$d', date: day.add(const Duration(hours: 7)), kind: FeedKind.morning, productId: 'np1', label: tr('Brit Premium Sport 30/20'), grams: m, kcal: m * 3.95));
      entries.add(FeedingEntry(
          id: 'ne$d', date: day.add(const Duration(hours: 18)), kind: FeedKind.evening, productId: 'np1', label: tr('Brit Premium Sport 30/20'), grams: e, kcal: e * 3.95));
      final pcs = (rnd.nextInt(25) + 5).toDouble();
      entries.add(FeedingEntry(
          id: 'nt$d', date: day.add(const Duration(hours: 17)), kind: FeedKind.treat, productId: 'np3', label: tr('Trainer Kostki treningowe wołowe'), grams: pcs * 1.5, pieces: pcs, kcal: pcs * 1.5 * 3.4));
      entries.add(FeedingEntry(
          id: 'ns$d', date: day.add(const Duration(hours: 8)), kind: FeedKind.supplement, productId: 'np5', label: tr('Antiflexi'), grams: 2, pieces: 1, kcal: 5));
    }
    entries.add(FeedingEntry(
        id: 'nm0', date: today.add(const Duration(hours: 7)), kind: FeedKind.morning, productId: 'np1', label: tr('Brit Premium Sport 30/20'), grams: 160, kcal: 160 * 3.95));
    supplements = [SupplementPlan(id: 'ns1', name: tr('Antiflexi'), dose: tr('1 tabletka'), productId: 'np5', hour: 8)];
    doseHistory = [];
    targetByDay = {};
    await _save();
  }
}

/// Odczyt zapisu żywienia do zmiennych tymczasowych.
class _NutState {
  List<FoodProduct> products = [];
  List<FoodBag> bags = [];
  List<FeedingEntry> entries = [];
  List<SupplementPlan> supplements = [];
  List<DoseChange> doses = [];
  Map<String, double> targets = {};
  NutritionSettings settings = NutritionSettings();
  DateTime? lastSync;
  final Map<String, List<dynamic>> bad = {};
  Map<String, Map<String, dynamic>> pending = {};
  final Map<String, dynamic> extra = {};

  static const _known = {
    'version', 'products', 'bags', 'entries', 'supplements', 'doses', 'targets', 'settings', 'lastSync', //
    'pendingTrainings',
  };

  static _NutState parse(String? raw) {
    final x = _NutState();
    if (raw == null) return x;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    List<T> sec<T>(String name, T Function(Map<String, dynamic>) f) {
      final (ok, b) = readList(j[name], f);
      if (b.isNotEmpty) x.bad[name] = b;
      return ok;
    }

    x.products = sec('products', FoodProduct.fromJson);
    x.bags = sec('bags', FoodBag.fromJson);
    x.entries = sec('entries', FeedingEntry.fromJson);
    x.supplements = sec('supplements', SupplementPlan.fromJson);
    x.doses = sec('doses', DoseChange.fromJson);
    x.targets = {
      for (final e in ((j['targets'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toDouble()
    };
    x.settings = j['settings'] == null ? NutritionSettings() : NutritionSettings.fromJson(j['settings']);
    x.lastSync = j['lastSync'] == null ? null : DateTime.parse(j['lastSync']);
    x.pending = {
      for (final e in ((j['pendingTrainings'] as Map?) ?? {}).entries)
        e.key as String: Map<String, dynamic>.from(e.value as Map)
    };
    for (final e in j.entries) {
      if (!_known.contains(e.key)) x.extra[e.key] = e.value;
    }
    return x;
  }
}

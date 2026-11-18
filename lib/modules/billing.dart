import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'module_store.dart';

/// Jeden plan subskrypcji (np. miesięczny, roczny) z cenami ze Sklepu Google Play.
class PremiumPlan {
  final ProductDetails details;
  final String basePlanId;
  final String price; // cena regularna, np. „14,99 zł”
  final String period; // ISO 8601, np. P1M, P1Y
  final String? trial; // np. „7 dni za darmo”
  const PremiumPlan(this.details, this.basePlanId, this.price, this.period, this.trial);

  bool get yearly => period == 'P1Y';
  String get label => switch (period) {
        'P1Y' => 'Rocznie',
        'P1M' => 'Miesięcznie',
        'P3M' => 'Co 3 miesiące',
        'P6M' => 'Co 6 miesięcy',
        'P1W' => 'Tygodniowo',
        _ => basePlanId,
      };
  String get perLabel => switch (period) {
        'P1Y' => '/ rok',
        'P1M' => '/ mies.',
        'P3M' => '/ 3 mies.',
        'P6M' => '/ 6 mies.',
        'P1W' => '/ tydz.',
        _ => '',
      };
}

/// Płatności Premium przez Google Play (subskrypcja).
///
/// W Konsoli Google Play trzeba utworzyć subskrypcję o identyfikatorze
/// [productId] z planami podstawowymi (np. „miesieczny” P1M i „roczny” P1Y).
/// Dopóki aplikacja nie jest w Sklepie Play (np. APK z GitHuba), plany się nie
/// wczytają i działa tylko przełącznik testowy.
class Billing extends ChangeNotifier {
  Billing._();
  static final Billing instance = Billing._();

  static const productId = 'valkor_premium';

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool initialized = false;
  bool storeAvailable = false;
  bool busy = false;
  String? message;
  List<PremiumPlan> plans = [];

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Sklep działa i ma skonfigurowaną subskrypcję – prawdziwe płatności.
  bool get live => storeAvailable && plans.isNotEmpty;

  Future<void> init() async {
    if (!supported || initialized) return;
    initialized = true;
    try {
      final iap = InAppPurchase.instance;
      _sub = iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        message = 'Błąd płatności: $e';
        busy = false;
        notifyListeners();
      });
      storeAvailable = await iap.isAvailable();
      if (!storeAvailable) return;
      final r = await iap.queryProductDetails({productId});
      plans = _plans(r.productDetails);
      if (live) await _refreshEntitlement();
    } catch (e) {
      debugPrint('Płatności niedostępne: $e');
    } finally {
      notifyListeners();
    }
  }

  List<PremiumPlan> _plans(List<ProductDetails> list) {
    final out = <PremiumPlan>[];
    for (final p in list) {
      if (p is! GooglePlayProductDetails) continue;
      final i = p.subscriptionIndex;
      final offers = p.productDetails.subscriptionOfferDetails;
      if (i == null || offers == null) continue;
      final o = offers[i];
      // Jeden wpis na plan podstawowy: wolimy ofertę z darmowym okresem próbnym.
      final phases = o.pricingPhases;
      final regular = phases.last;
      final free = phases.where((ph) => ph.priceAmountMicros == 0).firstOrNull;
      final trial = free == null ? null : '${_periodText(free.billingPeriod)} za darmo';
      final existing = out.indexWhere((e) => e.basePlanId == o.basePlanId);
      final plan = PremiumPlan(p, o.basePlanId, regular.formattedPrice, regular.billingPeriod, trial);
      if (existing < 0) {
        out.add(plan);
      } else if (trial != null && out[existing].trial == null) {
        out[existing] = plan;
      }
    }
    out.sort((a, b) => (a.yearly ? 1 : 0) - (b.yearly ? 1 : 0));
    return out;
  }

  static String _periodText(String iso) {
    final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
    if (m == null) return iso;
    final n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'D' => '$n ${n == 1 ? 'dzień' : 'dni'}',
      'W' => n == 1 ? '1 tydzień' : '$n tyg.',
      'M' => n == 1 ? '1 miesiąc' : '$n mies.',
      _ => n == 1 ? '1 rok' : '$n lat',
    };
  }

  /// Sprawdza w Google Play, czy subskrypcja jest aktywna.
  Future<void> _refreshEntitlement() async {
    final addition = InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final r = await addition.queryPastPurchases();
    if (r.error != null) return; // brak sieci itp. – zostawiamy ostatni znany stan
    final active = r.pastPurchases.any((p) => p.productID == productId && p.status != PurchaseStatus.error);
    for (final p in r.pastPurchases) {
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
    }
    await ModuleStore.instance.setPremium(active, source: PremiumSource.play);
  }

  Future<void> buy(PremiumPlan plan) async {
    if (!live || busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: GooglePlayPurchaseParam(productDetails: plan.details));
    } catch (e) {
      busy = false;
      message = 'Nie udało się rozpocząć płatności.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!live) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _refreshEntitlement();
      message = ModuleStore.instance.premium ? 'Premium przywrócone.' : 'Nie znaleziono aktywnej subskrypcji na tym koncie Google.';
    } catch (_) {
      message = 'Nie udało się sprawdzić zakupów.';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != productId) continue;
      switch (p.status) {
        case PurchaseStatus.pending:
          message = 'Płatność w toku – Premium włączy się po jej potwierdzeniu.';
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await ModuleStore.instance.setPremium(true, source: PremiumSource.play);
          message = 'Dziękujemy! Premium jest aktywne.';
          busy = false;
        case PurchaseStatus.error:
          message = 'Płatność nie powiodła się. Spróbuj ponownie.';
          busy = false;
        case PurchaseStatus.canceled:
          message = null;
          busy = false;
      }
      // Google wymaga potwierdzenia zakupu w ciągu 3 dni – inaczej zwraca pieniądze.
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

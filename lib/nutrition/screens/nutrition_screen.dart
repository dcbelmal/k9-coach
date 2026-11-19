import 'package:material_ui/material_ui.dart';

import '../../screens/forms.dart' show openWeightForm;
import '../../store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../advisor.dart';
import '../energy.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import 'diary_screen.dart';
import 'nutrition_charts.dart';
import 'nutrition_forms.dart';
import 'products_screen.dart';
import 'treat_training_screen.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

void openNutrition(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NutritionScreen()));

/// Dashboard modułu Żywienie.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _n.recordToday());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.restaurant_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text(tr('Żywienie')),
        ]),
        actions: [
          IconButton(
              tooltip: tr('Dziennik'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiaryScreen())),
              icon: const Icon(Icons.menu_book_rounded)),
          IconButton(
              tooltip: tr('Ustawienia'),
              onPressed: () => openNutritionSettings(context),
              icon: const Icon(Icons.tune_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openFeedingForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Karmienie'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: _n,
        builder: (context, _) {
          final plan = _n.plan;
          final dog = AppStore.instance.dog;
          if (dog == null) return const SizedBox();
          if (plan == null) {
            return EmptyState(
              icon: Icons.monitor_weight_rounded,
              title: tr('Podaj wagę psa'),
              text: tr('Dzienną dawkę liczę z masy ciała, wieku, aktywności i treningów.'),
              action: tr('Dodaj ważenie'),
              onAction: () => openWeightForm(context),
            );
          }
          final advice = NutritionAdvisor.analyze(_n);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
            FadeSlideIn(index: 0, child: _TodayCard(plan: plan)),
            gap12,
            FadeSlideIn(
              index: 1,
              child: Row(children: [
                Expanded(child: _StockTile()),
                const SizedBox(width: 12),
                Expanded(child: _TreatsTile(plan: plan)),
              ]),
            ),
            gap12,
            FadeSlideIn(
              index: 2,
              child: Row(children: [
                Expanded(child: _BalanceTile(plan: plan)),
                const SizedBox(width: 12),
                Expanded(child: _WeightTile()),
              ]),
            ),
            gap12,
            FadeSlideIn(index: 3, child: _AiCard(advice: advice)),
            gap12,
            const FadeSlideIn(index: 4, child: _Actions()),
            gap12,
            FadeSlideIn(index: 5, child: NutritionChartsCard()),
            gap12,
            FadeSlideIn(index: 6, child: _HowCard(plan: plan)),
          ]);
        },
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final DailyPlan plan;
  const _TodayCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final food = _n.mainProduct;
    final eatenShare = plan.targetKcal <= 0 ? 0.0 : plan.eatenKcal / plan.targetKcal;
    final today = _n.entriesOn(DateTime.now());
    final morningDone = today.any((e) => e.kind == FeedKind.morning);
    final eveningDone = today.any((e) => e.kind == FeedKind.evening);
    return K9Card(
      gradient: LinearGradient(
        colors: [K9.orange.withValues(alpha: 0.22), K9.card],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RingGauge(
            value: eatenShare,
            size: 92,
            stroke: 10,
            color: eatenShare > 1.05 ? K9.red : K9.orange,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${plan.remainingGrams.round()}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
              Text(tr('g zostało'), style: TextStyle(color: K9.muted, fontSize: 10.5)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Dzisiejsza porcja'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
              Text(tr('{0} g karmy', [plan.dailyGrams.round()]),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(tr('{0} kcal · zjedzone {1} kcal', [plan.targetKcal.round(), plan.eatenKcal.round()]),
                  style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13)),
              if (food != null)
                Text(food.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: K9.faint, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _MealButton(
              kind: FeedKind.morning,
              grams: plan.morningGrams,
              done: morningDone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MealButton(
              kind: FeedKind.evening,
              grams: plan.eveningGrams,
              done: eveningDone,
            ),
          ),
        ]),
        if (food == null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => addProductFlow(context, type: ProductType.dry),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(tr('Dodaj karmę główną')),
          ),
        ],
      ]),
    );
  }
}

class _MealButton extends StatelessWidget {
  final FeedKind kind;
  final double grams;
  final bool done;
  const _MealButton({required this.kind, required this.grams, required this.done});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? K9.green.withValues(alpha: 0.14) : K9.cardHi,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openFeedingForm(context, kind: kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(done ? Icons.check_circle_rounded : kind.icon, color: done ? K9.green : kind.color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind == FeedKind.morning ? tr('Rano') : tr('Wieczorem'), style: const TextStyle(color: K9.muted, fontSize: 12)),
                Text('${grams.round()} g', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final f = _n.mainForecast;
    final low = f?.daysLeft != null && f!.daysLeft! <= _n.settings.buyLeadDays;
    return K9Card(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StockScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_rounded, color: low ? K9.red : K9.orange, size: 20),
          const SizedBox(width: 6),
          Text(tr('Magazyn'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        if (f == null) ...[
          Text(tr('Brak worka'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(tr('Dodaj otwarty worek'), style: TextStyle(color: K9.muted, fontSize: 12)),
        ] else ...[
          Text(fmtGrams(f.remainingGrams), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: f.fraction,
              minHeight: 6,
              backgroundColor: K9.cardHi,
              color: low ? K9.red : (f.fraction < 0.3 ? K9.yellow : K9.green),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              f.emptyDate == null
                  ? tr('brak danych o zużyciu')
                  : tr('do {0} · kup {1}', [fmtDateShort(f.emptyDate!), relDays(f.buyDate!)]),
              maxLines: 2,
              style: TextStyle(color: low ? K9.red : K9.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _TreatsTile extends StatelessWidget {
  final DailyPlan plan;
  const _TreatsTile({required this.plan});
  @override
  Widget build(BuildContext context) {
    final pcs = _n.entriesOn(DateTime.now()).where((e) => e.kind == FeedKind.treat).fold(0.0, (a, e) => a + (e.pieces ?? 1));
    return K9Card(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProductsScreen(initialType: ProductType.treat))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cookie_rounded, color: K9.yellow, size: 20),
          SizedBox(width: 6),
          Text(tr('Przysmaki dziś'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text(tr('{0} kcal', [plan.treatsKcal.round()]), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('{0} szt. · {1}% dnia', [fmtNum(pcs, 0), (plan.treatsShare * 100).round()]),
            style: TextStyle(color: plan.treatsShare > 0.15 ? K9.yellow : K9.muted, fontSize: 12)),
        Text(tr('odjęte od karmy'), style: TextStyle(color: K9.faint, fontSize: 12)),
      ]),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final DailyPlan plan;
  const _BalanceTile({required this.plan});
  @override
  Widget build(BuildContext context) {
    final b = plan.balance;
    final over = b > plan.targetKcal * 0.05;
    final c = b.abs() < plan.targetKcal * 0.05 ? K9.green : (over ? K9.red : K9.text);
    return K9Card(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiaryScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.balance_rounded, color: K9.orange, size: 20),
          SizedBox(width: 6),
          Text(tr('Bilans kalorii'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text(b > 0 ? tr('+{0} kcal', [b.round()]) : tr('{0} kcal', [(-b).round()]),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 4),
        Text(b > 0 ? tr('ponad cel dnia') : tr('zostało do celu'), style: const TextStyle(color: K9.muted, fontSize: 12)),
        Text(
            plan.trainingKcal > 0
                ? tr('cel ok. {0} (bieg +{1})', [plan.targetKcal.round(), plan.trainingKcal.round()])
                : tr('cel ok. {0} kcal', [plan.targetKcal.round()]),
            style: const TextStyle(color: K9.faint, fontSize: 12)),
      ]),
    );
  }
}

class _WeightTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dog = AppStore.instance.dog!;
    final t = dog.targetWeightKg;
    return K9Card(
      onTap: () => openWeightForm(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.monitor_weight_rounded, color: Color(0xFFBF5AF2), size: 20),
          SizedBox(width: 6),
          Text(tr('Waga'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text(tr('{0} kg', [fmtNum(dog.weightKg ?? 0)]), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(t == null ? tr('cel: nie ustawiono') : tr('cel {0} kg ({1})', [fmtNum(t), _n.settings.goal.label.toLowerCase()]),
            maxLines: 2, style: const TextStyle(color: K9.muted, fontSize: 12)),
      ]),
    );
  }
}

class _AiCard extends StatelessWidget {
  final List<Advice> advice;
  const _AiCard({required this.advice});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Asystent AI – rekomendacje'), icon: Icons.auto_awesome_rounded),
        for (final a in advice.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(a.icon, a.color, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(a.text, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
                  if (a.adjustPct != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () async {
                          final s = _n.settings;
                          final next = (s.adjustPct + a.adjustPct!).clamp(-30, 30).toDouble();
                          s.adjustPct = next.abs() < 0.5 ? 0 : next;
                          if (!context.mounted) return;
                          if (!await saveGuarded(context, () => _n.saveSettings(s, reason: 'rekomendacja AI'))) return;
                          if (context.mounted) toast(context, tr('Dawka zaktualizowana'));
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(a.title.startsWith('Aktywna korekta')
                            ? tr('Wyzeruj korektę')
                            : tr('Zastosuj {0}{1}%', [a.adjustPct! > 0 ? '+' : '', a.adjustPct!.round()])),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions();
  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final items = <(IconData, String, VoidCallback)>[
      (Icons.qr_code_scanner_rounded, tr('Skanuj'), () => addProductFlow(context)),
      (Icons.sports_rounded, tr('Trening z nagrodami'), () => openTreatTraining(context)),
      (Icons.cookie_rounded, tr('Przysmak'), () => openFeedingForm(context, kind: FeedKind.treat)),
      (Icons.medication_liquid_rounded, tr('Suplementy'), () => push(const SupplementsScreen())),
      (Icons.inventory_2_rounded, tr('Magazyn'), () => push(const StockScreen())),
      (Icons.list_alt_rounded, tr('Produkty'), () => push(const ProductsScreen())),
      (Icons.menu_book_rounded, tr('Dziennik'), () => push(const DiaryScreen())),
      (Icons.tune_rounded, tr('Ustawienia'), () => openNutritionSettings(context)),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      padding: EdgeInsets.zero,
      children: [
        for (final it in items)
          K9Card(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            onTap: it.$3,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(it.$1, color: K9.orange, size: 28),
              const SizedBox(height: 8),
              Text(it.$2,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15)),
            ]),
          ),
      ],
    );
  }
}

class _HowCard extends StatelessWidget {
  final DailyPlan plan;
  const _HowCard({required this.plan});
  @override
  Widget build(BuildContext context) {
    final dog = AppStore.instance.dog!;
    final months = Energy.ageMonths(dog.birthDate);
    return K9Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calculate_rounded, color: K9.orange),
          title: Text(tr('Jak liczę dawkę'), style: TextStyle(fontWeight: FontWeight.w700)),
          children: [
            _row(tr('Masa do obliczeń'), tr('{0} kg', [fmtNum(plan.basisKg)])),
            _row(tr('Zapotrzebowanie spoczynkowe (RER)'), tr('{0} kcal', [plan.rer.round()])),
            _row(tr('Mnożnik ({0}, {1})', [Energy.lifeStageLabel(months, adultKg: Energy.expectedAdultKg(dog)), _n.settings.activity.label.toLowerCase()]),
                '× ${fmtNum(plan.factor, 2)}'),
            _row(tr('Zapotrzebowanie bazowe'), tr('{0} kcal', [plan.baseKcal.round()])),
            _row(tr('Dodatkowy wysiłek (bieg z dystansem)'), tr('+{0} kcal', [plan.trainingKcal.round()])),
            if (plan.adjustPct != 0) _row(tr('Korekta'), '${plan.adjustPct > 0 ? '+' : ''}${plan.adjustPct.round()}%'),
            _row(tr('Cel na dziś (orientacyjnie)'), tr('{0} kcal', [plan.targetKcal.round()])),
            _row(tr('Typowy zakres dla psa o tych danych'), tr('{0}–{1} kcal', [plan.lowKcal.round(), plan.highKcal.round()])),
            _row(tr('Przysmaki i suplementy'), tr('−{0} kcal', [(plan.treatsKcal + plan.supplementsKcal).round()])),
            _row(tr('Kaloryczność karmy'), tr('{0} kcal/100 g', [(plan.kcalPerGram * 100).round()])),
            const SizedBox(height: 8),
            for (final n in plan.notes)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('• $n', style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            Text(
                tr('Wzory: RER = 70 × masa^0,75, mnożniki wg NRC 2006 i WSAVA/AAHA. Psy o tej samej masie potrzebują nawet o 20% mniej lub więcej – to punkt startowy, nie dawka ustalona dla Twojego psa. Koryguj co 2–3 tygodnie wg masy i BCS, a przy chorobie, ciąży, laktacji lub silnej redukcji ustal dietę z lekarzem weterynarii.'),
                style: TextStyle(color: K9.faint, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: K9.muted, fontSize: 13))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Magazyn
// ---------------------------------------------------------------------------

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Magazyn karmy'))),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openBagForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: _n,
        builder: (context, _) {
          final active = _n.activeBags;
          final done = _n.bags.where((b) => !b.active).toList()..sort((a, b) => b.finished!.compareTo(a.finished!));
          if (_n.bags.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_rounded,
              title: tr('Pusty magazyn'),
              text: tr('Dodaj otwarty worek karmy. Odejmę każde karmienie i przewidzę, kiedy się skończy.'),
              action: tr('Dodaj worek'),
              onAction: () => openBagForm(context),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            for (final b in active) _BagCard(f: _n.forecast(b)),
            if (done.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(tr('Skończone'), style: TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
              ),
              for (final b in done.take(20))
                ListRow(
                  icon: Icons.inventory_2_outlined,
                  color: K9.faint,
                  title: _n.product(b.productId)?.title ?? tr('Produkt usunięty'),
                  subtitle:
                      tr('{0} · {1} – {2} ({3} dni)', [fmtGrams(b.initialGrams), fmtDateShort(b.opened), fmtDateShort(b.finished!), b.finished!.difference(b.opened).inDays]),
                  onTap: () => openBagForm(context, existing: b),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

class _BagCard extends StatelessWidget {
  final StockForecast f;
  const _BagCard({required this.f});
  @override
  Widget build(BuildContext context) {
    final low = f.daysLeft != null && f.daysLeft! <= _n.settings.buyLeadDays;
    final c = low ? K9.red : (f.fraction < 0.3 ? K9.yellow : K9.green);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: K9Card(
        onTap: () => openBagForm(context, existing: f.bag),
        child: Row(children: [
          RingGauge(
            value: f.fraction,
            size: 64,
            stroke: 7,
            color: c,
            center: Text('${(f.fraction * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.product?.title ?? tr('Produkt usunięty'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(tr('Zostało {0} z {1}', [fmtGrams(f.remainingGrams), fmtGrams(f.bag.initialGrams)]),
                  style: const TextStyle(color: K9.muted, fontSize: 13)),
              if (f.emptyDate != null)
                Text(
                    tr('Zużycie {0} g/dzień · koniec {1} ({2})', [f.dailyUse.round(), fmtDateShort(f.emptyDate!), relDays(f.emptyDate!)]),
                    style: TextStyle(color: low ? K9.red : K9.faint, fontSize: 12)),
              if (f.buyDate != null)
                Text(tr('Kup nowy: {0}', [fmtDateShort(f.buyDate!)]), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suplementy
// ---------------------------------------------------------------------------

class SupplementsScreen extends StatelessWidget {
  const SupplementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Suplementy'))),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openSupplementPlanForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: _n,
        builder: (context, _) {
          if (_n.supplements.isEmpty) {
            return EmptyState(
              icon: Icons.medication_liquid_rounded,
              title: tr('Brak suplementów'),
              text: tr('Dodaj suplement i godzinę, a codziennie przypomnę o podaniu.'),
              action: tr('Dodaj suplement'),
              onAction: () => openSupplementPlanForm(context),
            );
          }
          final today = _n.entriesOn(DateTime.now()).where((e) => e.kind == FeedKind.supplement).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            for (final s in _n.supplements)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: K9Card(
                  padding: const EdgeInsets.all(12),
                  onTap: () => openSupplementPlanForm(context, existing: s),
                  child: Row(children: [
                    IconBadge(Icons.medication_liquid_rounded, s.active ? K9.green : K9.faint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            tr('{0}codziennie {1}:{2}', [s.dose.isEmpty ? '' : '${s.dose} · ', s.hour.toString().padLeft(2, '0'), s.minute.toString().padLeft(2, '0')]),
                            style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                      ]),
                    ),
                    if (today.any((e) => e.productId == s.productId && s.productId != null || e.label == s.name))
                      const Icon(Icons.check_circle_rounded, color: K9.green)
                    else
                      TextButton(
                        onPressed: () async {
                          final p = _n.product(s.productId);
                          final e = p?.pieceGrams != null
                              ? _n.entryFor(p, FeedKind.supplement, pieces: 1)
                              : _n.entryFor(p, FeedKind.supplement, grams: 1);
                          e.label = s.name;
                          if (!context.mounted) return;
                          if (!await saveGuarded(context, () => _n.addEntry(e))) return;
                        },
                        child: Text(tr('Podano')),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

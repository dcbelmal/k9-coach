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
        title: const Row(children: [
          Icon(Icons.restaurant_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text('Żywienie'),
        ]),
        actions: [
          IconButton(
              tooltip: 'Dziennik',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiaryScreen())),
              icon: const Icon(Icons.menu_book_rounded)),
          IconButton(
              tooltip: 'Ustawienia',
              onPressed: () => openNutritionSettings(context),
              icon: const Icon(Icons.tune_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openFeedingForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Karmienie', style: TextStyle(fontWeight: FontWeight.w700)),
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
              title: 'Podaj wagę psa',
              text: 'Dzienną dawkę liczę z masy ciała, wieku, aktywności i treningów.',
              action: 'Dodaj ważenie',
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
              const Text('g zostało', style: TextStyle(color: K9.muted, fontSize: 10.5)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Dzisiejsza porcja', style: TextStyle(color: K9.muted, fontSize: 12.5)),
              Text('${plan.dailyGrams.round()} g karmy',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('${plan.targetKcal.round()} kcal · zjedzone ${plan.eatenKcal.round()} kcal',
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
            label: const Text('Dodaj karmę główną'),
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
                Text(kind == FeedKind.morning ? 'Rano' : 'Wieczorem', style: const TextStyle(color: K9.muted, fontSize: 12)),
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
          const Text('Magazyn', style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        if (f == null) ...[
          const Text('Brak worka', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Text('Dodaj otwarty worek', style: TextStyle(color: K9.muted, fontSize: 12)),
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
                  ? 'brak danych o zużyciu'
                  : 'do ${fmtDateShort(f.emptyDate!)} · kup ${relDays(f.buyDate!)}',
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
        const Row(children: [
          Icon(Icons.cookie_rounded, color: K9.yellow, size: 20),
          SizedBox(width: 6),
          Text('Przysmaki dziś', style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text('${plan.treatsKcal.round()} kcal', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${fmtNum(pcs, 0)} szt. · ${(plan.treatsShare * 100).round()}% dnia',
            style: TextStyle(color: plan.treatsShare > 0.15 ? K9.yellow : K9.muted, fontSize: 12)),
        const Text('odjęte od karmy', style: TextStyle(color: K9.faint, fontSize: 12)),
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
        const Row(children: [
          Icon(Icons.balance_rounded, color: K9.orange, size: 20),
          SizedBox(width: 6),
          Text('Bilans kalorii', style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text(b > 0 ? '+${b.round()} kcal' : '${(-b).round()} kcal',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 4),
        Text(b > 0 ? 'ponad cel dnia' : 'zostało do celu', style: const TextStyle(color: K9.muted, fontSize: 12)),
        Text(
            plan.trainingKcal > 0
                ? 'cel ${plan.targetKcal.round()} (trening +${plan.trainingKcal.round()})'
                : 'cel ${plan.targetKcal.round()} kcal',
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
        const Row(children: [
          Icon(Icons.monitor_weight_rounded, color: Color(0xFFBF5AF2), size: 20),
          SizedBox(width: 6),
          Text('Waga', style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Text('${fmtNum(dog.weightKg ?? 0)} kg', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(t == null ? 'cel: nie ustawiono' : 'cel ${fmtNum(t)} kg (${_n.settings.goal.label.toLowerCase()})',
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
        const SectionTitle('Asystent AI – rekomendacje', icon: Icons.auto_awesome_rounded),
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
                          await _n.saveSettings(s, reason: 'rekomendacja AI');
                          if (context.mounted) toast(context, 'Dawka zaktualizowana');
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(a.title.startsWith('Aktywna korekta')
                            ? 'Wyzeruj korektę'
                            : 'Zastosuj ${a.adjustPct! > 0 ? '+' : ''}${a.adjustPct!.round()}%'),
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
      (Icons.qr_code_scanner_rounded, 'Skanuj', () => addProductFlow(context)),
      (Icons.sports_rounded, 'Trening z nagrodami', () => openTreatTraining(context)),
      (Icons.cookie_rounded, 'Przysmak', () => openFeedingForm(context, kind: FeedKind.treat)),
      (Icons.medication_liquid_rounded, 'Suplementy', () => push(const SupplementsScreen())),
      (Icons.inventory_2_rounded, 'Magazyn', () => push(const StockScreen())),
      (Icons.list_alt_rounded, 'Produkty', () => push(const ProductsScreen())),
      (Icons.menu_book_rounded, 'Dziennik', () => push(const DiaryScreen())),
      (Icons.tune_rounded, 'Ustawienia', () => openNutritionSettings(context)),
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
          title: const Text('Jak liczę dawkę', style: TextStyle(fontWeight: FontWeight.w700)),
          children: [
            _row('Masa do obliczeń', '${fmtNum(plan.basisKg)} kg'),
            _row('Zapotrzebowanie spoczynkowe (RER)', '${plan.rer.round()} kcal'),
            _row('Mnożnik (${Energy.lifeStageLabel(months)}, ${_n.settings.activity.label.toLowerCase()})',
                '× ${fmtNum(plan.factor, 2)}'),
            _row('Podstawa', '${plan.baseKcal.round()} kcal'),
            _row('Treningi dziś', '+${plan.trainingKcal.round()} kcal'),
            if (plan.adjustPct != 0) _row('Korekta', '${plan.adjustPct > 0 ? '+' : ''}${plan.adjustPct.round()}%'),
            _row('Cel na dziś', '${plan.targetKcal.round()} kcal'),
            _row('Przysmaki i suplementy', '−${(plan.treatsKcal + plan.supplementsKcal).round()} kcal'),
            _row('Kaloryczność karmy', '${(plan.kcalPerGram * 100).round()} kcal/100 g'),
            const SizedBox(height: 8),
            for (final n in plan.notes)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('• $n', style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            const Text(
                'Wzory: RER = 70 × masa^0,75 (NRC/WSAVA). Dawka jest orientacyjna – obserwuj kondycję psa i skonsultuj dietę z weterynarzem.',
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
      appBar: AppBar(title: const Text('Magazyn karmy')),
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
              title: 'Pusty magazyn',
              text: 'Dodaj otwarty worek karmy. Odejmę każde karmienie i przewidzę, kiedy się skończy.',
              action: 'Dodaj worek',
              onAction: () => openBagForm(context),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            for (final b in active) _BagCard(f: _n.forecast(b)),
            if (done.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text('Skończone', style: TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
              ),
              for (final b in done.take(20))
                ListRow(
                  icon: Icons.inventory_2_outlined,
                  color: K9.faint,
                  title: _n.product(b.productId)?.title ?? 'Produkt usunięty',
                  subtitle:
                      '${fmtGrams(b.initialGrams)} · ${fmtDateShort(b.opened)} – ${fmtDateShort(b.finished!)} (${b.finished!.difference(b.opened).inDays} dni)',
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
              Text(f.product?.title ?? 'Produkt usunięty', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('Zostało ${fmtGrams(f.remainingGrams)} z ${fmtGrams(f.bag.initialGrams)}',
                  style: const TextStyle(color: K9.muted, fontSize: 13)),
              if (f.emptyDate != null)
                Text(
                    'Zużycie ${f.dailyUse.round()} g/dzień · koniec ${fmtDateShort(f.emptyDate!)} (${relDays(f.emptyDate!)})',
                    style: TextStyle(color: low ? K9.red : K9.faint, fontSize: 12)),
              if (f.buyDate != null)
                Text('Kup nowy: ${fmtDateShort(f.buyDate!)}', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
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
      appBar: AppBar(title: const Text('Suplementy')),
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
              title: 'Brak suplementów',
              text: 'Dodaj suplement i godzinę, a codziennie przypomnę o podaniu.',
              action: 'Dodaj suplement',
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
                            '${s.dose.isEmpty ? '' : '${s.dose} · '}codziennie ${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
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
                          await _n.addEntry(e);
                        },
                        child: const Text('Podano'),
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

import 'package:material_ui/material_ui.dart';

import '../../screens/forms.dart' show openWeightForm;
import '../../store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../energy.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import 'nutrition_charts.dart';
import 'nutrition_forms.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

/// Dziennik żywienia: posiłki, przysmaki, suplementy, waga, aktywność, historia zmian dawki.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});
  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DateTime day = dayOnly(DateTime.now());
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Dziennik żywienia'))),
      floatingActionButton: tab == 0
          ? FloatingActionButton(
              backgroundColor: K9.orange,
              foregroundColor: Colors.black,
              onPressed: () => openFeedingForm(context,
                  date: sameDay(day, DateTime.now()) ? null : day.add(const Duration(hours: 12))),
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      body: ListenableBuilder(
        listenable: _n,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
          Segmented(items: [tr('Dzień'), tr('Wykresy'), tr('Zmiany')], index: tab, onChanged: (i) => setState(() => tab = i)),
          gap12,
          if (tab == 0) ..._dayView(context),
          if (tab == 1) const NutritionChartsCard(full: true),
          if (tab == 2) ..._history(),
        ]),
      ),
    );
  }

  List<Widget> _dayView(BuildContext context) {
    final app = AppStore.instance;
    final list = _n.entriesOn(day)..sort((a, b) => a.date.compareTo(b.date));
    final plan = _n.planFor(day);
    final trainings = app.doneTrainings.where((t) => sameDay(t.date, day)).toList();
    final weight = app.weights.where((w) => sameDay(w.date, day)).toList();
    final kg = app.dog?.weightKg ?? 0;
    Widget section(FeedKind k) {
      final items = list.where((e) => e.kind == k).toList();
      if (items.isEmpty && (k == FeedKind.extra || k == FeedKind.supplement)) return const SizedBox();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(children: [
            Icon(k.icon, color: k.color, size: 18),
            const SizedBox(width: 6),
            Text(k.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (items.isNotEmpty)
              Text(tr('{0} kcal', [items.fold(0.0, (a, e) => a + e.kcal).round()]), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          ]),
        ),
        if (items.isEmpty)
          TextButton(
            onPressed: () => openFeedingForm(context, kind: k, date: sameDay(day, DateTime.now()) ? null : day.add(Duration(hours: k == FeedKind.morning ? 7 : 18))),
            child: Text(tr('+ dodaj')),
          ),
        for (final e in items)
          ListRow(
            icon: k.icon,
            color: k.color,
            title: e.label.isEmpty ? k.label : e.label,
            subtitle: [
              fmtTime(e.date),
              e.pieces != null ? '${fmtNum(e.pieces!, 0)} szt. (${e.grams.round()} g)' : '${e.grams.round()} g',
              '${e.kcal.round()} kcal',
              if (e.trainingId != null) 'z treningu',
            ].join(' · '),
            onTap: () => openFeedingForm(context, existing: e),
          ),
      ]);
    }

    return [
      Row(
        children: [
          IconButton(
            tooltip: tr('Poprzedni'),
            onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              sameDay(day, DateTime.now()) ? tr('Dziś, {0}', [fmtDate(day)]) : '${fmtWeekday(day)}, ${fmtDate(day)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: tr('Następny'),
            onPressed: sameDay(day, DateTime.now())
                ? null
                : () => setState(() => day = day.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      if (plan != null)
        K9Card(
          child: Row(children: [
            Expanded(child: StatValue(label: tr('Zjedzone'), value: '${plan.eatenKcal.round()}', unit: 'kcal')),
            Expanded(child: StatValue(label: tr('Cel'), value: '${plan.targetKcal.round()}', unit: 'kcal')),
            Expanded(
                child: StatValue(
                    label: tr('Bilans'),
                    value: '${plan.balance > 0 ? '+' : ''}${plan.balance.round()}',
                    unit: 'kcal',
                    color: plan.balance > 0 ? K9.red : K9.green)),
          ]),
        ),
      gap12,
      K9Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final k in FeedKind.values) section(k),
        ]),
      ),
      gap12,
      K9Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(tr('Waga i aktywność'), icon: Icons.directions_run_rounded),
          if (weight.isEmpty)
            ListRow(
              icon: Icons.monitor_weight_rounded,
              color: const Color(0xFFBF5AF2),
              title: tr('Brak ważenia'),
              subtitle: tr('Dodaj pomiar wagi'),
              onTap: () => openWeightForm(context),
            ),
          for (final w in weight)
            ListRow(
              icon: Icons.monitor_weight_rounded,
              color: const Color(0xFFBF5AF2),
              title: tr('{0} kg', [fmtNum(w.kg)]),
              subtitle: tr('Ważenie'),
              trailing: const SizedBox(),
            ),
          if (trainings.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(tr('Brak treningów tego dnia.'), style: TextStyle(color: K9.muted)),
            ),
          for (final t in trainings)
            ListRow(
              icon: t.discipline.icon,
              color: t.discipline.color,
              title: t.discipline.label,
              subtitle:
                  tr('{0}{1} · +{2} kcal', [fmtDuration(t.durationMin), t.distanceKm != null ? tr(' · {0} km', [fmtKm(t.distanceKm!)]) : '', Energy.trainingKcal(t, kg).round()]),
              trailing: const SizedBox(),
            ),
        ]),
      ),
    ];
  }

  List<Widget> _history() {
    if (_n.doseHistory.isEmpty) {
      return [
        EmptyState(
            icon: Icons.history_rounded,
            title: tr('Brak zmian dawki'),
            text: tr('Tu zapiszę każdą zmianę porcji: po treningu, zmianie celu, karmy lub rekomendacji AI.'))
      ];
    }
    return [
      K9Card(
        child: Column(children: [
          for (final d in _n.doseHistory.take(60))
            ListRow(
              icon: d.toGrams > d.fromGrams ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: d.toGrams > d.fromGrams ? K9.orange : K9.blue,
              title: '${d.fromGrams.round()} g → ${d.toGrams.round()} g',
              subtitle: '${fmtDate(d.date)}, ${fmtTime(d.date)} · ${tr(d.reason)}',
              trailing: const SizedBox(),
            ),
        ]),
      ),
    ];
  }
}

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forms.dart';
import 'home.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

class StatsScreen extends StatefulWidget {
  /// W zakładce Trening: bez własnego nagłówka i marginesu u góry.
  final bool embedded;
  const StatsScreen({super.key, this.embedded = false});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int period = 1; // 0 tydzień, 1 miesiąc, 2 rok
  bool showKm = true;

  static const _months = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];

  /// Zakres okresu i podział na słupki.
  (DateTime, DateTime, List<(DateTime, DateTime, String)>) _buckets() {
    final now = DateTime.now();
    switch (period) {
      case 0:
        final s = startOfWeek(now);
        return (
          s,
          s.plusDays(7),
          [
            for (var i = 0; i < 7; i++)
              (s.plusDays(i), s.plusDays(i + 1), fmtWeekday(s.plusDays(i)))
          ]
        );
      case 1:
        final s = DateTime(now.year, now.month, 1);
        final e = DateTime(now.year, now.month + 1, 1);
        final n = e.difference(s).inCalDays;
        return (
          s,
          e,
          [
            for (var i = 0; i < n; i++)
              (DateTime(s.year, s.month, i + 1), DateTime(s.year, s.month, i + 2), '${i + 1}')
          ]
        );
      default:
        final s = DateTime(now.year, 1, 1);
        return (
          s,
          DateTime(now.year + 1, 1, 1),
          [for (var m = 0; m < 12; m++) (DateTime(now.year, m + 1, 1), DateTime(now.year, m + 2, 1), _months[m])]
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final (from, to, buckets) = _buckets();
        final totals = s.statsBetween(from, to);
        final values = [
          for (final b in buckets)
            showKm ? s.statsBetween(b.$1, b.$2).km : s.statsBetween(b.$1, b.$2).minutes.toDouble()
        ];
        final inPeriod =
            s.doneTrainings.where((t) => !t.date.isBefore(from) && t.date.isBefore(to)).toList();

        return SafeArea(
          bottom: false,
          top: !widget.embedded,
          child: ListView(
              key: PageStorageKey('stats-${widget.embedded}'),
              padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 8, 16, 120),
              children: [
            if (!widget.embedded) ...[
              Row(children: [
                Icon(Icons.bar_chart_rounded, color: K9.orange),
                SizedBox(width: 10),
                Text(tr('Statystyki'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
              gap16,
            ],
            Segmented(
                items: [tr('Tydzień'), tr('Miesiąc'), tr('Rok')],
                index: period,
                onChanged: (i) => setState(() => period = i)),
            gap16,
            FadeSlideIn(
              key: ValueKey('tot$period'),
              child: K9Card(
                child: Row(children: [
                  Expanded(
                      child: StatValue(
                          icon: Icons.directions_run_rounded,
                          label: tr('Dystans'),
                          value: fmtKm(totals.km),
                          unit: 'km')),
                  Expanded(
                      child: StatValue(
                          icon: Icons.timer_outlined, label: tr('Czas treningu'), value: fmtDurationShort(totals.minutes))),
                  Expanded(
                      child: StatValue(
                          icon: Icons.event_available_rounded, label: tr('Treningi'), value: '${totals.count}')),
                ]),
              ),
            ),
            gap12,
            K9Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(showKm ? tr('Dystans (km)') : tr('Czas treningów (min)'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  _MiniToggle(
                      a: 'km', b: tr('czas'), first: showKm, onChanged: (v) => setState(() => showKm = v)),
                ]),
                const SizedBox(height: 18),
                SizedBox(height: 190, child: _BarChart(values: values, labels: [for (final b in buckets) b.$3])),
              ]),
            ),
            gap12,
            _TypesCard(items: inPeriod),
            gap12,
            _LoadCard(s: s),
            gap12,
            _WeightCard(s: s),
            gap12,
            _GoalsCard(s: s),
          ]),
        );
      },
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String a, b;
  final bool first;
  final ValueChanged<bool> onChanged;
  const _MiniToggle({required this.a, required this.b, required this.first, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget item(String t, bool sel, bool v) => GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? K9.orange : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(t,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5, color: sel ? Colors.black : K9.muted)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: K9.cardHi, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [item(a, first, true), item(b, !first, false)]),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  const _BarChart({required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold(0.0, math.max);
    final top = maxV <= 0 ? 10.0 : (maxV * 1.2);
    final many = values.length > 12;
    return BarChart(
      BarChartData(
        maxY: top,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) => const FlLine(color: K9.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: top / 4,
              getTitlesWidget: (v, m) => Text(v.round().toString(),
                  style: const TextStyle(color: K9.faint, fontSize: 10.5)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox();
                if (many && i % 5 != 0 && i != labels.length - 1) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: const TextStyle(color: K9.muted, fontSize: 10.5)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => K9.cardHi,
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                fmtNum(rod.toY), const TextStyle(color: K9.text, fontWeight: FontWeight.w700)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: many ? 5 : 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                gradient: const LinearGradient(
                    colors: [K9.orangeDeep, K9.orange, Color(0xFFFFA24C)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: top, color: K9.cardHi.withValues(alpha: 0.5)),
              ),
            ]),
        ],
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }
}

class _TypesCard extends StatefulWidget {
  final List<TrainingSession> items;
  const _TypesCard({required this.items});
  @override
  State<_TypesCard> createState() => _TypesCardState();
}

class _TypesCardState extends State<_TypesCard> {
  int touched = -1;

  @override
  Widget build(BuildContext context) {
    final counts = <Discipline, int>{};
    for (final t in widget.items) {
      counts[t.discipline] = (counts[t.discipline] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.items.length;
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Typy treningów'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (total == 0)
          Text(tr('Brak treningów w tym okresie.'), style: TextStyle(color: K9.muted))
        else
          Row(children: [
            SizedBox(
              width: 130,
              height: 130,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 38,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(touchCallback: (e, r) {
                    setState(() => touched = (e.isInterestedForInteractions && r?.touchedSection != null)
                        ? r!.touchedSection!.touchedSectionIndex
                        : -1);
                  }),
                  sections: [
                    for (final (i, e) in entries.indexed)
                      PieChartSectionData(
                        value: e.value.toDouble(),
                        color: e.key.color,
                        radius: i == touched ? 24 : 18,
                        showTitle: false,
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 500),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(children: [
                for (final e in entries.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: e.key.color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key.label, style: const TextStyle(fontSize: 13))),
                      Text('${(e.value * 100 / total).round()}%',
                          style: const TextStyle(color: K9.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
          ]),
      ]),
    );
  }
}

/// Monitor obciążenia treningowego (ostatnie 8 tygodni).
class _LoadCard extends StatelessWidget {
  final AppStore s;
  const _LoadCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final r = s.readiness;
    final c = readinessColor(r.level);
    final w0 = startOfWeek(DateTime.now());
    final weeks = [
      for (var i = 7; i >= 0; i--)
        s.doneTrainings
            .where((t) =>
                !t.date.isBefore(w0.plusDays(-(7 * i))) &&
                t.date.isBefore(w0.plusDays(-(7 * (i - 1)))))
            .fold(0.0, (a, t) => a + t.load)
    ];
    final maxW = weeks.fold(0.0, math.max);
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(tr('Monitor obciążenia treningowego'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(r.label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(r.advice, style: const TextStyle(color: K9.muted, fontSize: 13)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxW <= 0 ? 10 : maxW * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    interval: 1,
                    getTitlesWidget: (v, m) => Text(v.toInt() == 7 ? tr('teraz') : tr('-{0} tydz.', [7 - v.toInt()]),
                        style: const TextStyle(color: K9.faint, fontSize: 9.5)),
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < weeks.length; i++) FlSpot(i.toDouble(), weeks[i])],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  barWidth: 3,
                  color: K9.orange,
                  dotData: FlDotData(
                    getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: i == 7 ? 5 : 2.5, color: i == 7 ? c : K9.orange, strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [K9.orange.withValues(alpha: 0.35), K9.orange.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
            r.ratio == 0
                ? tr('Obciążenie = czas × intensywność (RPE).')
                : tr('Obciążenie 7 dni / średnia tygodniowa z 4 tygodni: {0}. Umowny zakres „jak zwykle” 0,8–1,3 – to orientacyjny wskaźnik zmiany obciążenia (ACWR), niezwalidowany u psów i nie mierzy zmęczenia.', [fmtNum(r.ratio, 2)]),
            style: const TextStyle(color: K9.faint, fontSize: 11.5)),
      ]),
    );
  }
}

class _WeightCard extends StatelessWidget {
  final AppStore s;
  const _WeightCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final w = s.weights;
    final target = s.dog?.targetWeightKg;
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('Waga'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (w.isNotEmpty)
                Text(
                  tr('{0} kg', [fmtNum(w.last.kg)]),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: K9.orange),
                ),
              IconButton(
                tooltip: tr('Dodaj'),
                onPressed: () => openWeightForm(context),
                icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange),
              ),
            ],
          ),
          if (w.length < 2)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('Dodaj co najmniej dwa pomiary, aby zobaczyć wykres.'), style: TextStyle(color: K9.muted)),
            )
          else
            SizedBox(
              height: 170,
              child: WeightChart(weights: w, target: target),
            ),
        ],
      ),
    );
  }
}

class WeightChart extends StatelessWidget {
  final List<WeightEntry> weights;
  final double? target;
  const WeightChart({super.key, required this.weights, this.target});

  @override
  Widget build(BuildContext context) {
    final t0 = weights.first.date;
    double x(DateTime d) => d.difference(t0).inCalDays.toDouble();
    final ys = [...weights.map((e) => e.kg), ?target];
    final minY = (ys.reduce(math.min) - 1).floorToDouble();
    final maxY = (ys.reduce(math.max) + 1).ceilToDouble();
    final span = x(weights.last.date);
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: span <= 0 ? 1 : span,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: math.max(1, ((maxY - minY) / 4).roundToDouble()),
          getDrawingHorizontalLine: (_) => const FlLine(color: K9.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        extraLinesData: target == null
            ? null
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: target!,
                  color: K9.green.withValues(alpha: 0.7),
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: const TextStyle(color: K9.green, fontSize: 11, fontWeight: FontWeight.w600),
                    labelResolver: (_) => tr('cel {0} kg', [fmtNum(target!)]),
                  ),
                ),
              ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: math.max(1, ((maxY - minY) / 4).roundToDouble()),
              getTitlesWidget: (v, m) =>
                  Text(v.round().toString(), style: const TextStyle(color: K9.faint, fontSize: 10.5)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: span <= 0 ? 1 : span / 3,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(fmtDateShort(t0.plusDays(v.round())),
                    style: const TextStyle(color: K9.muted, fontSize: 10.5)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => K9.cardHi,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(tr('{0} kg', [fmtNum(s.y)]),
                    const TextStyle(color: K9.text, fontWeight: FontWeight.w700))
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final w in weights) FlSpot(x(w.date), w.kg)],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 3,
            color: K9.orange,
            dotData: FlDotData(
              getDotPainter: (s, p, b, i) =>
                  FlDotCirclePainter(radius: 3, color: K9.bg, strokeColor: K9.orange, strokeWidth: 2),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [K9.orange.withValues(alpha: 0.3), K9.orange.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsCard extends StatelessWidget {
  final AppStore s;
  const _GoalsCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearKm = s.statsBetween(DateTime(now.year), DateTime(now.year + 1)).km;
    final weekKm = s.thisWeek.km;
    final goal = s.dog?.weeklyKmGoal ?? 30;
    final yearGoal = goal * 52;
    final w = s.dog?.weightKg;
    final t = s.dog?.targetWeightKg;
    final rows = <(String, String, double, Color)>[
      (tr('Kilometry w tym tygodniu'), tr('{0} / {1} km', [fmtKm(weekKm), fmtKm(goal)]), goal <= 0 ? 0 : weekKm / goal, K9.orange),
      (tr('Kilometry w tym roku'), tr('{0} / {1} km', [fmtKm(yearKm), fmtKm(yearGoal)]), yearGoal <= 0 ? 0 : yearKm / yearGoal, K9.yellow),
      if (w != null && t != null && t > 0)
        (tr('Docelowa masa'), tr('{0} / {1} kg', [fmtNum(w), fmtNum(t)]), math.min(w, t) / math.max(w, t), K9.green),
    ];
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Postęp do celów'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        for (final r in rows) ...[
          Row(children: [
            RingGauge(
              value: r.$3,
              size: 52,
              stroke: 6,
              color: r.$4,
              center: Text('${(r.$3 * 100).clamp(0, 999).round()}%',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(r.$2, style: const TextStyle(color: K9.muted, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

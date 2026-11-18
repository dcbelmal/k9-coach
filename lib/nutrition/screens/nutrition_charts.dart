import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../nutrition_store.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

/// Wykresy: kalorie, karma, przysmaki, waga, zapas w worku.
class NutritionChartsCard extends StatefulWidget {
  final bool full;
  const NutritionChartsCard({super.key, this.full = false});
  @override
  State<NutritionChartsCard> createState() => _NutritionChartsCardState();
}

class _NutritionChartsCardState extends State<NutritionChartsCard> {
  int metric = 0;
  static const _names = ['Kalorie', 'Karma', 'Przysmaki', 'Waga', 'Worek'];

  @override
  Widget build(BuildContext context) {
    final days = _n.lastDays(widget.full ? 30 : 14);
    final labels = [for (final d in days) fmtDayMonth(d.day)];
    Widget chart;
    String caption;
    switch (metric) {
      case 0:
        chart = _Bars(values: [for (final d in days) d.kcal], labels: labels, line: [for (final d in days) d.targetKcal]);
        caption = 'Spożyte kcal dziennie, linia – cel dnia (z treningami).';
      case 1:
        chart = _Bars(values: [for (final d in days) d.mealGrams], labels: labels);
        caption = 'Gramy karmy w posiłkach.';
      case 2:
        chart = _Bars(values: [for (final d in days) d.treatKcal], labels: labels, color: K9.yellow);
        final pcs = days.fold(0.0, (a, d) => a + d.treatPieces);
        caption = 'Kalorie z przysmaków · razem ${fmtNum(pcs, 0)} szt. w ${days.length} dni.';
      case 3:
        final from = DateTime.now().subtract(const Duration(days: 120));
        final w = AppStore.instance.weights.where((e) => e.date.isAfter(from)).toList();
        chart = w.length < 2
            ? Center(child: Text(tr('Za mało ważeń'), style: const TextStyle(color: K9.muted)))
            : _Line(
                points: [for (final e in w) FlSpot(e.date.millisecondsSinceEpoch / 8.64e7, e.kg)],
                target: AppStore.instance.dog?.targetWeightKg,
                label: (x) => fmtDayMonth(DateTime.fromMillisecondsSinceEpoch((x * 8.64e7).round())));
        caption = 'Waga z ostatnich 4 miesięcy, przerywana – cel.';
      default:
        final f = _n.mainForecast;
        if (f == null || f.dailyUse <= 0) {
          chart = Center(child: Text(tr('Dodaj worek karmy w magazynie'), style: TextStyle(color: K9.muted)));
          caption = '';
        } else {
          final opened = dayOnly(f.bag.opened);
          final today = dayOnly(DateTime.now());
          final pts = <FlSpot>[];
          for (var d = opened; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
            final used = _n.entries
                .where((e) =>
                    e.productId == f.bag.productId && !e.date.isBefore(f.bag.opened) && e.date.isBefore(d.add(const Duration(days: 1))))
                .fold(0.0, (a, e) => a + e.grams);
            pts.add(FlSpot(d.difference(opened).inDays.toDouble(), math.max(0, f.bag.initialGrams - used + f.bag.correctionGrams) / 1000));
          }
          final tx = today.difference(opened).inDays.toDouble();
          final ex = f.emptyDate!.difference(opened).inDays.toDouble();
          chart = _Line(
            points: pts,
            forecast: [FlSpot(tx, f.remainingGrams / 1000), FlSpot(math.max(ex, tx + 1), 0)],
            label: (x) => fmtDayMonth(opened.add(Duration(days: x.round()))),
          );
          caption = tr('Zapas w worku (kg). Przerywana – prognoza: koniec {0}, zakup nowego worka {1}.', [fmtDateShort(f.emptyDate!), fmtDateShort(f.buyDate!)]);
        }
    }

    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Wykresy'), icon: Icons.insights_rounded),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < _names.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tr(_names[i])),
                  selected: metric == i,
                  showCheckmark: false,
                  selectedColor: K9.orange,
                  backgroundColor: K9.cardHi,
                  side: BorderSide.none,
                  labelStyle: TextStyle(color: metric == i ? Colors.black : K9.text, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (_) => setState(() => metric = i),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 180, child: chart),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(caption, style: const TextStyle(color: K9.faint, fontSize: 11.5)),
        ],
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final List<double>? line;
  final Color color;
  const _Bars({required this.values, required this.labels, this.line, this.color = K9.orange});

  @override
  Widget build(BuildContext context) {
    final maxV = [...values, ...?line].fold(0.0, math.max);
    final top = maxV <= 0 ? 10.0 : maxV * 1.2;
    final step = values.length > 14 ? 7 : 3;
    return Stack(children: [
      BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
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
                reservedSize: 36,
                interval: top / 4,
                getTitlesWidget: (v, m) =>
                    Text(v.round().toString(), style: const TextStyle(color: K9.faint, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox();
                  if ((labels.length - 1 - i) % step != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i], style: const TextStyle(color: K9.muted, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => K9.cardHi,
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem('${labels[g.x]}\n${rod.toY.round()}',
                  const TextStyle(color: K9.text, fontWeight: FontWeight.w700)),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: values.length > 14 ? 6 : 12,
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
      if (line != null && line!.any((v) => v > 0))
        Padding(
          padding: const EdgeInsets.only(left: 36, bottom: 22),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: top,
              minX: -0.5,
              maxX: values.length - 0.5,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < line!.length; i++)
                      if (line![i] > 0) FlSpot(i.toDouble(), line![i])
                  ],
                  color: K9.green,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
    ]);
  }
}

class _Line extends StatelessWidget {
  final List<FlSpot> points;
  final List<FlSpot>? forecast;
  final double? target;
  final String Function(double) label;
  const _Line({required this.points, required this.label, this.forecast, this.target});

  @override
  Widget build(BuildContext context) {
    final ys = [...points.map((p) => p.y), ...?forecast?.map((p) => p.y), ?target];
    var minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = math.max(0.5, (maxY - minY) * 0.15);
    minY = math.max(0, minY - pad);
    maxY = maxY + pad;
    final xs = [...points.map((p) => p.x), ...?forecast?.map((p) => p.x)];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: minX,
        maxX: maxX <= minX ? minX + 1 : maxX,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: K9.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => Text(fmtNum(v), style: const TextStyle(color: K9.faint, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1, ((maxX - minX) / 4).roundToDouble()),
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label(v), style: const TextStyle(color: K9.muted, fontSize: 10)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => K9.cardHi,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem('${label(s.x)}\n${fmtNum(s.y)}', const TextStyle(color: K9.text, fontWeight: FontWeight.w700))
            ],
          ),
        ),
        extraLinesData: target == null
            ? null
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(y: target!, color: K9.green, strokeWidth: 1.5, dashArray: [6, 4]),
              ]),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            preventCurveOverShooting: true,
            color: K9.orange,
            barWidth: 3,
            dotData: FlDotData(show: points.length < 20),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [K9.orange.withValues(alpha: 0.3), K9.orange.withValues(alpha: 0)],
              ),
            ),
          ),
          if (forecast != null)
            LineChartBarData(
              spots: forecast!,
              color: K9.red,
              barWidth: 2,
              dashArray: [6, 4],
              dotData: const FlDotData(show: true),
            ),
        ],
      ),
    );
  }
}

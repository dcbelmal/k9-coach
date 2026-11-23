import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../models.dart';
import '../modules/module_store.dart';
import '../modules/premium_screen.dart';
import '../nutrition/nutrition_store.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'perf_energy.dart';
import 'perf_model.dart';
import 'perf_period.dart';
import 'perf_repository.dart';

void openPerformance(BuildContext context, {TrainingSession? session}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PerformanceScreen(session: session)));

const zoneColors = [K9.muted, Color(0xFF30B0C7), K9.orange, K9.red];

String zoneLabel(PerfZone z) => switch (z) {
  PerfZone.rest => tr('Odpoczynek'),
  PerfZone.low => tr('Niska (stęp)'),
  PerfZone.moderate => tr('Umiarkowana (kłus)'),
  PerfZone.high => tr('Wysoka (galop)'),
};

String periodLabel(PerfPeriod p) => switch (p) {
  PerfPeriod.session => tr('Trening'),
  PerfPeriod.day => tr('Dzień'),
  PerfPeriod.week => tr('Tydzień'),
  PerfPeriod.month => tr('Miesiąc'),
  PerfPeriod.year => tr('Rok'),
  PerfPeriod.custom => tr('Zakres'),
};

String _km(double? m) => m == null ? '–' : '${fmtKm(m / 1000)} km';
String _kmh(double? ms) => ms == null ? '–' : '${fmtNum(ms * 3.6)} km/h';
String _dur(double? sec) => sec == null ? '–' : fmtDuration((sec / 60).round());

/// Valkor Performance – centrum analizy aktywności psa (Premium).
class PerformanceScreen extends StatelessWidget {
  final TrainingSession? session;
  const PerformanceScreen({super.key, this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleStore.instance,
      builder: (context, _) => ModuleStore.instance.premium ? _Body(session: session) : const _Locked(),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Valkor Performance'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          K9Card(
            gradient: const LinearGradient(colors: [Color(0xFF2A1A0C), K9.card]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.insights_rounded, color: K9.orange, size: 36),
                gap12,
                Text(
                  tr('Zaawansowane statystyki psa'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Dystans psa i przewodnika, prędkości, strefy aktywności, obciążenie, rekordy, szacowany wydatek energii i bilans z żywieniem – dla treningu, dnia, tygodnia, miesiąca i roku.',
                  ),
                  style: const TextStyle(color: K9.muted),
                ),
                gap16,
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: Text(tr('Odblokuj w Premium')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wyliczone dane dla wybranego okresu.
class _Data {
  final PerfSummary cur, prev, allTime;
  final List<TrendPoint> trend;
  final List<SessionMetrics> prevSessionsForCompare;
  final EnergyPeriod energy;
  const _Data(this.cur, this.prev, this.allTime, this.trend, this.prevSessionsForCompare, this.energy);
}

class _Body extends StatefulWidget {
  final TrainingSession? session;
  const _Body({this.session});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late PerfPeriod period = widget.session != null ? PerfPeriod.session : PerfPeriod.week;
  DateTime anchor = DateTime.now();
  DateRange? custom;
  String? sessionId;
  final Set<Discipline> only = {};
  Future<_Data>? _future;

  @override
  void initState() {
    super.initState();
    sessionId = widget.session?.id;
    if (widget.session != null) anchor = widget.session!.date;
    AppStore.instance.addListener(_reload);
    NutritionStore.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_reload);
    NutritionStore.instance.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final f = _compute();
    setState(() {
      _future = f;
    });
  }

  List<TrainingSession> get _filtered {
    final all = AppStore.instance.doneTrainings.where((t) => only.isEmpty || only.contains(t.discipline)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return all;
  }

  TrainingSession? get _session {
    final list = _filtered;
    if (list.isEmpty) return null;
    for (final t in list) {
      if (t.id == sessionId) return t;
    }
    return list.last;
  }

  DateRange get _range => rangeFor(period, anchor, custom: custom);

  Future<_Data> _compute() async {
    final repo = PerfRepository.instance;
    final s = AppStore.instance;
    final all = s.doneTrainings.toList();
    PerfSummary cur, prev;
    var trendPts = <TrendPoint>[];
    var prevCompare = <SessionMetrics>[];
    DateRange energyRange;
    if (period == PerfPeriod.session) {
      final t = _session;
      if (t == null) {
        cur = const PerfSummary([]);
        prev = const PerfSummary([]);
      } else {
        cur = PerfSummary(await repo.metricsFor([t]));
        // Porównanie z poprzednim treningiem tej samej dyscypliny.
        final before =
            all.where((x) => x.discipline == t.discipline && x.date.isBefore(t.date) && x.id != t.id).toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        prevCompare = before.isEmpty ? [] : await repo.metricsFor([before.last]);
        prev = PerfSummary(prevCompare);
      }
      energyRange = rangeFor(PerfPeriod.day, t?.date ?? anchor);
    } else {
      final r = _range;
      final (sel, dups) = selectSessions(all, r, only: only);
      final (selPrev, dupsPrev) = selectSessions(all, previousRange(period, r), only: only);
      final m = await repo.metricsFor(sel);
      cur = PerfSummary(m, duplicatesSkipped: dups);
      prev = PerfSummary(await repo.metricsFor(selPrev), duplicatesSkipped: dupsPrev);
      if (period != PerfPeriod.day) trendPts = trend(m, r);
      energyRange = r;
    }
    final (allSel, allDups) = selectSessions(
      all,
      DateRange(DateTime(1990), DateTime.now().add(const Duration(days: 1))),
      only: only,
    );
    final allTime = PerfSummary(await repo.metricsFor(allSel), duplicatesSkipped: allDups);

    // Bilans: dni z zakresu (najwyżej rok), treningi wszystkich dyscyplin –
    // wydatek energii nie zależy od filtra.
    final n = NutritionStore.instance;
    final energyDays = <DayEnergy>[];
    final days = daysIn(energyRange);
    final (daySel, _) = selectSessions(all, energyRange);
    final dayMetrics = await repo.metricsFor(daySel);
    for (final d in days.length > 366 ? days.sublist(days.length - 366) : days) {
      final entries = n.entriesOn(d);
      final plan = n.planFor(d);
      final (extra, routine) = activityKcal(dayMetrics.where((m) => _sameDay(m.session.date, d)));
      energyDays.add(
        DayEnergy(
          d,
          eatenKcal: entries.isEmpty ? null : entries.fold<double>(0, (a, e) => a + e.kcal),
          rerKcal: plan?.rer,
          baseKcal: plan?.baseKcal,
          extraKcal: extra,
          routineKcal: routine,
        ),
      );
    }
    return _Data(cur, prev, allTime, trendPts, prevCompare, EnergyPeriod(energyDays));
  }

  void _shift(int dir) {
    setState(() {
      switch (period) {
        case PerfPeriod.session:
          final list = _filtered;
          final cur = _session;
          if (cur == null) return;
          final i = list.indexOf(cur) + dir;
          if (i >= 0 && i < list.length) sessionId = list[i].id;
        case PerfPeriod.day:
          anchor = anchor.add(Duration(days: dir));
        case PerfPeriod.week:
          anchor = anchor.add(Duration(days: 7 * dir));
        case PerfPeriod.month:
          anchor = DateTime(anchor.year, anchor.month + dir, 1);
        case PerfPeriod.year:
          anchor = DateTime(anchor.year + dir, 1, 1);
        case PerfPeriod.custom:
          final r = _range;
          final n = r.days;
          custom = DateRange(r.from.add(Duration(days: n * dir)), r.to.add(Duration(days: n * dir)));
      }
    });
    _reload();
  }

  bool get _canGoNext {
    if (period == PerfPeriod.session) {
      final list = _filtered;
      final cur = _session;
      return cur != null && list.indexOf(cur) < list.length - 1;
    }
    return _range.to.isBefore(DateTime.now());
  }

  String get _label {
    final r = _range;
    switch (period) {
      case PerfPeriod.session:
        final t = _session;
        return t == null ? tr('Brak treningów') : '${t.discipline.label} · ${fmtDateShort(t.date)}, ${fmtTime(t.date)}';
      case PerfPeriod.day:
        return fmtDate(r.from);
      case PerfPeriod.week:
      case PerfPeriod.custom:
        return '${fmtDateShort(r.from)} – ${fmtDateShort(r.to.subtract(const Duration(days: 1)))}';
      case PerfPeriod.month:
        return fmtMonthYear(r.from);
      case PerfPeriod.year:
        return '${r.from.year}';
    }
  }

  Future<void> _pickPeriod(PerfPeriod p) async {
    if (p == PerfPeriod.custom) {
      final now = DateTime.now();
      final r = _range;
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: DateTimeRange(start: r.from, end: r.to.subtract(const Duration(days: 1))),
      );
      if (picked == null || !mounted) return;
      custom = DateRange(picked.start, DateTime(picked.end.year, picked.end.month, picked.end.day + 1));
    }
    setState(() => period = p);
    _reload();
  }

  Future<void> _pickDisciplines() async {
    final sel = {...only};
    final res = await showModalBottomSheet<Set<Discipline>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetTitle(tr('Dyscypliny')),
                CheckboxListTile(value: sel.isEmpty, title: Text(tr('Wszystkie')), onChanged: (_) => set(sel.clear)),
                for (final d in Discipline.values)
                  CheckboxListTile(
                    value: sel.contains(d),
                    secondary: Icon(d.icon, color: d.color),
                    title: Text(d.label),
                    onChanged: (v) => set(() => v == true ? sel.add(d) : sel.remove(d)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: Text(tr('Zastosuj'))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      only
        ..clear()
        ..addAll(res);
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dog = AppStore.instance.dog;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Valkor Performance')),
          actions: [
            IconButton(
              tooltip: tr('Dyscypliny'),
              onPressed: _pickDisciplines,
              icon: Badge(
                isLabelVisible: only.isNotEmpty,
                backgroundColor: K9.orange,
                textColor: Colors.black,
                label: Text('${only.length}'),
                child: const Icon(Icons.filter_list_rounded),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: K9.orange,
            labelColor: K9.orange,
            unselectedLabelColor: K9.muted,
            tabs: [
              Tab(text: tr('Podsumowanie')),
              Tab(text: tr('Aktywność')),
              Tab(text: tr('Wydajność')),
              Tab(text: tr('Kondycja')),
              Tab(text: tr('Bilans energetyczny')),
            ],
          ),
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  for (final p in PerfPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: ValueKey('perf-${p.name}'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        showCheckmark: false,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: period == p ? Colors.black : K9.text,
                        ),
                        label: Text(periodLabel(p)),
                        selected: period == p,
                        onSelected: (_) => _pickPeriod(p),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: tr('Wcześniej'),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          [
                            dog?.name ?? '',
                            only.isEmpty ? tr('wszystkie dyscypliny') : only.map((d) => d.label).join(', '),
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: K9.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _canGoNext ? () => _shift(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: tr('Później'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_Data>(
                future: _future,
                builder: (context, snap) {
                  final d = snap.data;
                  if (d == null) {
                    return snap.hasError
                        ? Center(child: Text(tr('Nie udało się policzyć statystyk.')))
                        : const Center(child: CircularProgressIndicator());
                  }
                  final session = period == PerfPeriod.session;
                  return TabBarView(
                    children: [
                      _SummaryTab(d: d, session: session, period: period),
                      _ActivityTab(d: d, dog: dog),
                      _PerformanceTab(d: d, session: session),
                      _ConditionTab(d: d, range: _range, session: session),
                      _EnergyTab(d: d, session: session),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------------
// Elementy wspólne
// ---------------------------------------------------------------------------

ListView _tabList(List<Widget> children, String key) => ListView(
  key: PageStorageKey(key),
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
  children: [
    for (final c in children) ...[c, gap12],
  ],
);

/// Kafelek statystyki ze zmianą względem poprzedniego okresu.
class StatTile extends StatelessWidget {
  final String label, value;
  final double? change;
  final String? note;
  final IconData? icon;
  const StatTile(this.label, this.value, {super.key, this.change, this.note, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = change;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: K9.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: K9.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: K9.orange), const SizedBox(width: 5)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: K9.muted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(
            c == null ? (note ?? ' ') : '${c >= 0 ? '▲' : '▼'} ${fmtNum(c.abs(), 0)}%${note == null ? '' : ' · $note'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: c == null ? K9.faint : (c >= 0 ? K9.green : K9.yellow),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> tiles;
  const _Grid(this.tiles);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 3 : 2;
        final w = (c.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

/// Wskaźnik jakości danych.
class QualityBanner extends StatelessWidget {
  final PerfSummary s;
  const QualityBanner(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final q = s.quality;
    final (color, title, text) = switch (q) {
      DataQuality.good => (K9.green, tr('Dobra jakość danych'), tr('Pomiary trackera są gęste i ciągłe.')),
      DataQuality.partial => (
        K9.yellow,
        tr('Dane niepełne'),
        tr(
          'Były przerwy w sygnale albo rzadkie pomiary. Przez przerwy nie liczę dystansu, więc dystans i prędkości mogą być zaniżone.',
        ),
      ),
      DataQuality.insufficient => (
        K9.red,
        tr('Za mało danych z trackera'),
        tr('Statystyki psa są niedostępne. Pokazuję tylko dane zapisane w treningach.'),
      ),
      DataQuality.none => (
        K9.muted,
        tr('Brak danych z trackera'),
        tr(
          'W tym okresie nie ma treningów z trackerem na psie. Pokazuję czas, obciążenie i dystans wpisany w treningach.',
        ),
      ),
    };
    final cov = s.coverage;
    final extra = [
      if (cov != null) tr('pokrycie pomiarami {0}%', [(cov * 100).round()]),
      if (s.insufficientSessions > 0) tr('treningi z za małą ilością danych: {0}', [s.insufficientSessions]),
      if (s.duplicatesSkipped > 0) tr('pominięte duplikaty: {0}', [s.duplicatesSkipped]),
    ];
    return Container(
      key: const ValueKey('perf-quality'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(q == DataQuality.good ? Icons.verified_rounded : Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 2),
                Text([text, ...extra].join(' · '), style: const TextStyle(fontSize: 12.5, color: K9.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prosty wykres słupkowy.
class PerfBars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;

  /// Osobny kolor każdego słupka (np. strefy); null = [color].
  final List<Color>? colors;
  final String Function(double) fmt;
  const PerfBars({
    super.key,
    required this.values,
    required this.labels,
    this.color = K9.orange,
    this.colors,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold(0.0, math.max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.2;
    final step = (values.length / 7).ceil().clamp(1, 99);
    return SizedBox(
      height: 170,
      child: BarChart(
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
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => K9.cardHi,
              getTooltipItem: (g, _, r, _) =>
                  BarTooltipItem('${labels[g.x]}\n${fmt(r.toY)}', const TextStyle(color: K9.text, fontSize: 12)),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length || i % step != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i], style: const TextStyle(color: K9.muted, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: values.length > 20 ? 5 : 12,
                    color: colors != null && i < colors!.length ? colors![i] : color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _bucketLabel(DateTime d, int buckets) {
  if (buckets <= 7) return fmtWeekday(d);
  if (buckets == 12) return fmtMonthYear(d).substring(0, 3);
  if (buckets <= 31 && d.day != 1) return '${d.day}';
  return fmtDayMonth(d);
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Card(this.title, this.icon, this.children);

  @override
  Widget build(BuildContext context) => K9Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title, icon: icon),
        ...children,
      ],
    ),
  );
}

Widget _note(String text) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(text, style: const TextStyle(color: K9.faint, fontSize: 12)),
);

Widget _row(String label, String value, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: K9.muted)),
      ),
      Text(
        value,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    ],
  ),
);

// ---------------------------------------------------------------------------
// Zakładki
// ---------------------------------------------------------------------------

class _SummaryTab extends StatelessWidget {
  final _Data d;
  final bool session;
  final PerfPeriod period;
  const _SummaryTab({required this.d, required this.session, required this.period});

  @override
  Widget build(BuildContext context) {
    final c = d.cur, p = d.prev;
    final vs = session ? tr('vs poprzedni') : null;
    if (c.count == 0) {
      return _tabList([
        _Card(tr('Brak treningów'), Icons.insights_rounded, [
          Text(
            tr('W tym okresie nie ma zapisanych treningów. Zmień okres albo filtr dyscyplin.'),
            style: const TextStyle(color: K9.muted),
          ),
        ]),
      ], 'perf-sum');
    }
    final useDog = c.dogMeters != null;
    final trendVals = [for (final (_, s) in d.trend) ((useDog ? s.dogMeters : s.handlerMeters) ?? 0) / 1000];
    return _tabList([
      QualityBanner(c),
      _Grid([
        StatTile(
          tr('Dystans psa'),
          _km(c.dogMeters),
          icon: Icons.pets_rounded,
          change: pctChange(c.dogMeters, p.dogMeters),
          note: c.dogMeters == null
              ? tr('wymaga trackera')
              : (vs ?? (c.dogSessions < c.count ? tr('z {0} z {1} treningów', [c.dogSessions, c.count]) : null)),
        ),
        StatTile(
          tr('Dystans przewodnika'),
          _km(c.handlerMeters),
          icon: Icons.directions_walk_rounded,
          change: pctChange(c.handlerMeters, p.handlerMeters),
          note: vs,
        ),
        StatTile(
          tr('Pies / przewodnik'),
          c.ratio == null ? '–' : '× ${fmtNum(c.ratio!, 2)}',
          icon: Icons.compare_arrows_rounded,
          change: pctChange(c.ratio, p.ratio),
          note: vs,
        ),
        StatTile(
          tr('Czas ruchu'),
          _dur(c.movingSec),
          icon: Icons.timer_outlined,
          change: pctChange(c.movingSec, p.movingSec),
          note: vs,
        ),
        StatTile(
          tr('Śr. prędkość psa'),
          _kmh(c.avgSpeedMs),
          icon: Icons.speed_rounded,
          change: pctChange(c.avgSpeedMs, p.avgSpeedMs),
          note: vs,
        ),
        StatTile(
          tr('Kalorie (szacunek)'),
          c.kcal == null ? '–' : '~${c.kcal!.round()} kcal',
          icon: Icons.local_fire_department_rounded,
          change: pctChange(c.kcal, p.kcal),
          note: vs,
        ),
        StatTile(
          tr('Obciążenie'),
          '${c.load.round()}',
          icon: Icons.fitness_center_rounded,
          change: pctChange(c.load, p.load),
          note: vs,
        ),
        StatTile(
          tr('Treningi'),
          '${c.count}',
          icon: Icons.event_available_rounded,
          change: pctChange(c.count.toDouble(), p.count.toDouble()),
          note: vs,
        ),
      ]),
      if (trendVals.length > 1 && trendVals.any((v) => v > 0))
        _Card(useDog ? tr('Trend: dystans psa') : tr('Trend: dystans przewodnika'), Icons.show_chart_rounded, [
          PerfBars(
            values: trendVals,
            labels: [for (final (t, _) in d.trend) _bucketLabel(t, d.trend.length)],
            fmt: (v) => '${fmtKm(v)} km',
          ),
          _note(session ? '' : tr('Zmiana w kafelkach: porównanie z poprzednim okresem tej samej długości.')),
        ]),
      if (session && d.prevSessionsForCompare.isEmpty)
        _note(tr('To pierwszy trening tej dyscypliny – nie ma z czym porównać.')),
    ], 'perf-sum');
  }
}

class _ActivityTab extends StatelessWidget {
  final _Data d;
  final Dog? dog;
  const _ActivityTab({required this.d, required this.dog});

  @override
  Widget build(BuildContext context) {
    final c = d.cur;
    final z = c.zoneSec;
    final total = z.fold(0.0, (a, b) => a + b);
    final zones = GaitZones.forDog(heightCm: dog?.heightCm, kg: dog?.weightKg);
    final moving = [for (final (_, s) in d.trend) (s.movingSec ?? 0) / 60];
    return _tabList([
      QualityBanner(c),
      _Card(tr('Czas w strefach aktywności'), Icons.stacked_bar_chart_rounded, [
        if (total <= 0)
          Text(
            tr('Strefy wymagają trasy psa z trackera. W tym okresie jej nie ma albo danych jest za mało.'),
            style: const TextStyle(color: K9.muted),
          )
        else ...[
          PerfBars(
            values: [for (final v in z) v / 60],
            labels: [tr('Odp.'), tr('Niska'), tr('Umiark.'), tr('Wysoka')],
            colors: zoneColors,
            fmt: (v) => fmtDuration(v.round()),
          ),
          for (final zz in PerfZone.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 10, color: zoneColors[zz.index]),
                  const SizedBox(width: 8),
                  Expanded(child: Text(zoneLabel(zz))),
                  Text(
                    '${_dur(z[zz.index])} · ${(z[zz.index] / total * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
        _note(
          tr(
            'Progi dla tego psa: stęp do {0} km/h, kłus do {1} km/h, powyżej galop ({2}). Strefy opisują rodzaj ruchu, nie zmęczenie – ten sam kłus może być lekki dla jednego psa i ciężki dla innego.',
            [
              fmtNum(zones.walkTrot * 3.6),
              fmtNum(zones.trotGallop * 3.6),
              zones.fromHeight ? tr('z wysokości w kłębie') : tr('z masy – dodaj wzrost w profilu, będzie dokładniej'),
            ],
          ),
        ),
      ]),
      _Card(tr('Ruch i odpoczynek'), Icons.timelapse_rounded, [
        _row(tr('Czas ruchu psa'), _dur(c.dogMovingSec)),
        _row(tr('Szacowany odpoczynek'), _dur(c.restSec)),
        _row(tr('Bez pomiarów (przerwy w sygnale)'), _dur(c.noDataSec)),
        _row(
          tr('Intensywność (kłus i galop)'),
          c.intensityShare == null ? '–' : '${(c.intensityShare! * 100).round()}%',
        ),
        _note(tr('Czasu bez pomiarów nie liczę ani do ruchu, ani do odpoczynku.')),
      ]),
      if (moving.length > 1 && moving.any((v) => v > 0))
        _Card(tr('Trend: czas ruchu'), Icons.show_chart_rounded, [
          PerfBars(
            values: moving,
            labels: [for (final (t, _) in d.trend) _bucketLabel(t, d.trend.length)],
            color: const Color(0xFF30B0C7),
            fmt: (v) => fmtDuration(v.round()),
          ),
        ]),
    ], 'perf-act');
  }
}

class _PerformanceTab extends StatelessWidget {
  final _Data d;
  final bool session;
  const _PerformanceTab({required this.d, required this.session});

  Widget _rec(String label, PerfRecord? r, String Function(double) f) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.emoji_events_rounded, color: K9.yellow),
    title: Text(label),
    subtitle: Text(
      r == null ? tr('brak danych') : '${r.session.discipline.label} · ${fmtDate(r.session.date)}',
      style: const TextStyle(color: K9.muted, fontSize: 12.5),
    ),
    trailing: Text(r == null ? '–' : f(r.value), style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  @override
  Widget build(BuildContext context) {
    final c = d.cur, p = d.prev, a = d.allTime;
    return _tabList([
      _Grid([
        StatTile(tr('Śr. prędkość w ruchu'), _kmh(c.avgSpeedMs), change: pctChange(c.avgSpeedMs, p.avgSpeedMs)),
        StatTile(tr('Prędkość maks.'), _kmh(c.maxSpeedMs), change: pctChange(c.maxSpeedMs, p.maxSpeedMs)),
        StatTile(
          tr('Pies / przewodnik'),
          c.ratio == null ? '–' : '× ${fmtNum(c.ratio!, 2)}',
          change: pctChange(c.ratio, p.ratio),
        ),
        StatTile(tr('Przewyższenia'), '–', note: tr('niedostępne')),
      ]),
      _note(
        tr(
          'Przewyższeń nie liczę: trasa nie zapisuje wysokości, a wysokość z GPS ma błąd 10–20 m, więc suma podejść byłaby fikcyjna. Prędkość maksymalna – z odcinków co najmniej 3 s, bez niemożliwych skoków.',
        ),
      ),
      _Card(tr('Rekordy osobiste'), Icons.emoji_events_rounded, [
        _rec(tr('Najdłuższy dystans psa'), a.longestDog, (v) => _km(v)),
        _rec(tr('Najwyższa prędkość'), a.fastestDog, (v) => _kmh(v)),
        _rec(tr('Najszybsza średnia (od 1 km)'), a.fastestAvg, (v) => _kmh(v)),
        _rec(tr('Najdłuższy czas ruchu'), a.longestMoving, (v) => _dur(v)),
        _rec(tr('Największe obciążenie treningu'), a.highestLoad, (v) => '${v.round()}'),
        _note(
          tr(
            'Rekordy z całej historii psa (z uwzględnieniem filtra dyscyplin). Dystans i prędkości tylko z treningów z trackerem.',
          ),
        ),
      ]),
    ], 'perf-perf');
  }
}

class _ConditionTab extends StatelessWidget {
  final _Data d;
  final DateRange range;
  final bool session;
  const _ConditionTab({required this.d, required this.range, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    final c = d.cur;
    final r = s.readinessAt(session && c.sessions.isNotEmpty ? c.sessions.first.session.date : DateTime.now());
    final loads = [for (final (_, x) in d.trend) x.load];
    final w = s.weights.where((e) => range.contains(e.date)).toList();
    final allW = s.weights;
    return _tabList([
      _Card(tr('Obciążenie treningowe'), Icons.fitness_center_rounded, [
        _row(tr('W wybranym okresie'), '${c.load.round()}'),
        _row(tr('Ostatnie 7 dni do średniej z 4 tygodni'), r.ratio == 0 ? '–' : fmtNum(r.ratio, 2)),
        _row(tr('Ocena'), r.label),
        _note(r.advice),
        if (loads.length > 1 && loads.any((v) => v > 0)) ...[
          gap12,
          PerfBars(
            values: loads,
            labels: [for (final (t, _) in d.trend) _bucketLabel(t, d.trend.length)],
            color: K9.yellow,
            fmt: (v) => '${v.round()}',
          ),
        ],
        _note(tr('Obciążenie = minuty × intensywność (RPE 1–10) z treningów. To miara pracy, nie zmęczenia psa.')),
      ]),
      _Card(tr('Masa ciała a aktywność'), Icons.monitor_weight_rounded, [
        if (allW.isEmpty)
          Text(tr('Brak pomiarów masy. Dodaj je w module Historia masy.'), style: const TextStyle(color: K9.muted))
        else ...[
          _row(tr('Pomiary w okresie'), '${w.length}'),
          if (w.isNotEmpty) _row(tr('Masa na początku / na końcu'), '${fmtNum(w.first.kg)} / ${fmtNum(w.last.kg)} kg'),
          if (w.length >= 2)
            _row(tr('Zmiana'), '${w.last.kg >= w.first.kg ? '+' : ''}${fmtNum(w.last.kg - w.first.kg)} kg'),
          _row(tr('Dystans psa w okresie'), _km(c.dogMeters)),
          _row(tr('Kalorie ruchu (szacunek)'), c.kcal == null ? '–' : '~${c.kcal!.round()} kcal'),
          if (w.length >= 2) ...[gap12, _WeightActivityChart(weights: w, trend: d.trend)],
          _note(tr('Masa zależy głównie od karmienia – zestawienie pomaga zauważyć zależności, ale ich nie dowodzi.')),
        ],
      ]),
    ], 'perf-cond');
  }
}

/// Masa ciała (linia) na tle dystansu (słupki) w przedziałach trendu.
class _WeightActivityChart extends StatelessWidget {
  final List<WeightEntry> weights;
  final List<TrendPoint> trend;
  const _WeightActivityChart({required this.weights, required this.trend});

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const SizedBox.shrink();
    final t0 = trend.first.$1, t1 = trend.last.$1;
    final span = math.max(1, t1.difference(t0).inHours).toDouble();
    double x(DateTime d) =>
        (d.difference(t0).inHours / span * (trend.length - 1)).clamp(0, trend.length - 1).toDouble();
    final minW = weights.map((e) => e.kg).reduce(math.min), maxW = weights.map((e) => e.kg).reduce(math.max);
    final pad = math.max(0.5, (maxW - minW) * 0.2);
    final dist = [for (final (_, s) in trend) (s.dogMeters ?? s.handlerMeters ?? 0) / 1000];
    final maxD = dist.fold(0.0, math.max);
    double norm(double kg) => (kg - (minW - pad)) / ((maxW + pad) - (minW - pad));
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          if (maxD > 0)
            BarChart(
              BarChartData(
                maxY: maxD * 1.2,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                barTouchData: BarTouchData(enabled: false),
                barGroups: [
                  for (var i = 0; i < dist.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: dist[i],
                          width: dist.length > 20 ? 4 : 10,
                          color: K9.orange.withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          LineChart(
            LineChartData(
              minX: 0,
              maxX: (trend.length - 1).toDouble(),
              minY: 0,
              maxY: 1,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (final w in weights) FlSpot(x(w.date), norm(w.kg))],
                  color: K9.blue,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Text(
              tr('niebieska linia – masa, słupki – dystans'),
              style: const TextStyle(color: K9.faint, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnergyTab extends StatelessWidget {
  final _Data d;
  final bool session;
  const _EnergyTab({required this.d, required this.session});

  @override
  Widget build(BuildContext context) {
    final e = d.energy;
    final oneDay = e.days.length == 1;
    final day = oneDay ? e.days.first : null;
    final noWeight = e.days.every((x) => x.baseKcal == null);
    String k(double? v) => v == null ? '–' : '${v.round()} kcal';
    final withFood = e.withFood;
    return _tabList([
      _Card(oneDay ? tr('Bilans dnia') : tr('Bilans – średnio na dzień'), Icons.balance_rounded, [
        if (noWeight)
          Text(tr('Wpisz masę psa w profilu, a policzę zapotrzebowanie.'), style: const TextStyle(color: K9.muted))
        else ...[
          _row(tr('Spożyte kalorie'), k(oneDay ? day!.eatenKcal : e.avgEaten)),
          _row(tr('Zapotrzebowanie spoczynkowe (RER)'), k(oneDay ? day!.rerKcal : e.avgRer)),
          _row(tr('Zapotrzebowanie podstawowe'), k(oneDay ? day!.baseKcal : e.avgBase)),
          _row(tr('Dodatkowy wydatek z aktywności'), '+${k(oneDay ? day!.extraKcal : e.avgExtra ?? 0)}'),
          const Divider(color: K9.border),
          Builder(
            builder: (_) {
              final b = oneDay ? day!.balance : e.avgBalance;
              return _row(
                tr('Szacunkowy bilans'),
                b == null ? '–' : '${b >= 0 ? '+' : ''}${b.round()} kcal',
                color: b == null ? null : (b.abs() < 150 ? K9.green : K9.yellow),
              );
            },
          ),
          if ((oneDay ? day!.eatenKcal : e.avgEaten) == null)
            _note(tr('Brak wpisów karmienia w tym okresie – bilansu nie liczę. Zapisuj posiłki w module Żywienie.')),
          if (!oneDay && withFood.isNotEmpty)
            _note(tr('Średnia z {0} dni z wpisami karmienia (z {1} dni okresu).', [withFood.length, e.days.length])),
        ],
      ]),
      if (!oneDay && withFood.length > 1)
        _Card(tr('Bilans dzień po dniu'), Icons.bar_chart_rounded, [
          PerfBars(
            values: [for (final x in e.days) (x.balance ?? 0).abs()],
            colors: [for (final x in e.days) (x.balance ?? 0) >= 0 ? K9.orange : K9.blue],
            labels: [for (final x in e.days) e.days.length <= 7 ? fmtWeekday(x.day) : '${x.day.day}'],
            color: K9.blue,
            fmt: (v) => '${v.round()} kcal',
          ),
          _note(tr('Wysokość słupka = odchylenie od zapotrzebowania: pomarańczowy – nadwyżka, niebieski – niedobór.')),
        ]),
      _Card(tr('Wydatek na ruch w okresie'), Icons.local_fire_department_rounded, [
        _row(tr('Ponad zwykły dzień (doliczany)'), k(e.totalExtra)),
        _row(tr('Zwykła aktywność (już w podstawowym)'), k(e.totalRoutine)),
        if (d.cur.kcalFromHandler > 0)
          _note(
            tr(
              'W {0} treningach bez trackera liczę z dystansu przewodnika – pies zwykle przebiega więcej, więc to dolna granica.',
              [d.cur.kcalFromHandler],
            ),
          ),
      ]),
      _Card(tr('Jak liczę'), Icons.functions_rounded, [
        Text(
          tr(
            'RER = 70 × masa^0,75 (NRC 2006). Zapotrzebowanie podstawowe = RER × mnożnik z ustawień żywienia (wiek, kastracja, aktywność, cel) – obejmuje zwykłe spacery. Wydatek na ruch = masa × dystans psa w ruchu × 10,7 × masa^−0,316 J/(kg·m) (Taylor i wsp. 1982, koszt netto, ponad spoczynek). Doliczam go tylko za canicross, bikejoring i trening kondycyjny, żeby nie liczyć spacerów dwa razy.',
          ),
          style: const TextStyle(fontSize: 12.5, color: K9.muted),
        ),
        _note(
          tr(
            'To szacunek (błąd ok. ±25% i więcej), nie pomiar. Dawki karmy nie zmieniam automatycznie – oceniaj psa po masie i BCS, a zmiany ustalaj w module Żywienie.',
          ),
        ),
      ]),
    ], 'perf-energy');
  }
}

/// Karta wejścia do Valkor Performance (Start, Statystyki).
class PerformanceEntryCard extends StatelessWidget {
  const PerformanceEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final premium = ModuleStore.instance.premium;
    return K9Card(
      key: const ValueKey('perf-entry'),
      onTap: () => openPerformance(context),
      gradient: const LinearGradient(colors: [Color(0xFF2A1A0C), K9.card]),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: K9.orange, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Valkor Performance'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(
                  tr('Dystans psa, strefy, rekordy, kalorie i bilans'),
                  style: const TextStyle(color: K9.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Icon(premium ? Icons.chevron_right_rounded : Icons.lock_outline_rounded, color: K9.muted),
        ],
      ),
    );
  }
}

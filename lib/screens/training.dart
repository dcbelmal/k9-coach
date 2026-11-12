import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forms.dart';

class TrainingScreen extends StatefulWidget {
  final int initialTab;
  const TrainingScreen({super.key, this.initialTab = 0});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late int tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trening')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openTrainingForm(context, planned: tab == 1),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Segmented(
              items: const ['Dyscypliny', 'Plan', 'Historia'],
              index: tab,
              onChanged: (i) => setState(() => tab = i)),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (tab) {
              0 => const _Disciplines(key: ValueKey(0)),
              1 => const WeekPlan(key: ValueKey(1)),
              _ => const _History(key: ValueKey(2)),
            },
          ),
        ),
      ]),
    );
  }
}

class _Disciplines extends StatelessWidget {
  const _Disciplines({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          for (final (i, d) in Discipline.values.indexed) ...[
            FadeSlideIn(index: i, child: _DisciplineCard(d: d, s: s)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DisciplineCard extends StatelessWidget {
  final Discipline d;
  final AppStore s;
  const _DisciplineCard({required this.d, required this.s});

  @override
  Widget build(BuildContext context) {
    final list = s.doneTrainings.where((t) => t.discipline == d).toList();
    final last = list.isEmpty ? null : list.first;
    return K9Card(
      padding: EdgeInsets.zero,
      gradient: LinearGradient(
        colors: [K9.card, d.color.withValues(alpha: 0.22)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DisciplineScreen(discipline: d))),
      child: SizedBox(
        height: 78,
        child: Stack(children: [
          Positioned(
            right: -10,
            bottom: -18,
            child: Icon(d.icon, size: 96, color: d.color.withValues(alpha: 0.13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(d.icon, color: K9.orange, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          last == null
                              ? 'Brak treningów'
                              : '${list.length} treningów · ostatni ${relDays(last.date)}',
                          style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K9.orange),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Plan tygodnia z możliwością odhaczania treningów.
class WeekPlan extends StatefulWidget {
  const WeekPlan({super.key});
  @override
  State<WeekPlan> createState() => _WeekPlanState();
}

class _WeekPlanState extends State<WeekPlan> {
  DateTime week = startOfWeek(DateTime.now());

  int _weekNumber(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final firstJan = DateTime(thursday.year, 1, 1);
    return thursday.difference(firstJan).inDays ~/ 7 + 1;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        Row(children: [
          IconButton(
              onPressed: () => setState(() => week = week.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left_rounded, color: K9.orange)),
          Expanded(
            child: Column(children: [
              Text('Tydzień ${_weekNumber(week)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${fmtDateShort(week)} – ${fmtDateShort(week.add(const Duration(days: 6)))}',
                  style: const TextStyle(color: K9.muted, fontSize: 12.5)),
            ]),
          ),
          IconButton(
              onPressed: () => setState(() => week = week.add(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_right_rounded, color: K9.orange)),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < 7; i++) _DayRow(day: week.add(Duration(days: i)), s: s),
      ]),
    );
  }
}

class _DayRow extends StatelessWidget {
  final DateTime day;
  final AppStore s;
  const _DayRow({required this.day, required this.s});

  @override
  Widget build(BuildContext context) {
    final list = s.trainings.where((t) => sameDay(t.date, day)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final isToday = sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 46,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(children: [
              Text(fmtWeekday(day),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: isToday ? K9.orange : K9.text, fontSize: 13)),
              Text(fmtDayMonth(day), style: const TextStyle(color: K9.muted, fontSize: 11.5)),
            ]),
          ),
        ),
        Expanded(
          child: Column(children: [
            if (list.isEmpty)
              K9Card(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                color: K9.bg,
                onTap: () => openTrainingForm(context,
                    planned: day.isAfter(DateTime.now()), date: DateTime(day.year, day.month, day.day, 17)),
                child: const Row(children: [
                  Icon(Icons.add_rounded, color: K9.faint, size: 20),
                  SizedBox(width: 8),
                  Text('Dodaj trening', style: TextStyle(color: K9.faint)),
                ]),
              ),
            for (final t in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: K9Card(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  onTap: () => openTrainingForm(context, existing: t),
                  child: Row(children: [
                    IconBadge(t.discipline.icon, t.discipline.color, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            t.notes.isEmpty ? t.discipline.label : '${t.discipline.label} – ${t.notes}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                            [
                              fmtTime(t.date),
                              fmtDuration(t.durationMin),
                              if (t.distanceKm != null) '${fmtKm(t.distanceKm!)} km',
                            ].join(' · '),
                            style: const TextStyle(color: K9.muted, fontSize: 12)),
                      ]),
                    ),
                    Checkbox(
                      value: t.done,
                      activeColor: K9.orange,
                      checkColor: Colors.black,
                      side: const BorderSide(color: K9.orange, width: 1.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      onChanged: (v) {
                        t.done = v ?? false;
                        s.upsertTraining(t);
                      },
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _History extends StatelessWidget {
  const _History({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => TrainingHistoryList(items: s.doneTrainings.toList()),
    );
  }
}

class TrainingHistoryList extends StatelessWidget {
  final List<TrainingSession> items;
  final Widget? header;
  const TrainingHistoryList({super.key, required this.items, this.header});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(children: [
        ?header,
        const EmptyState(
            icon: Icons.directions_run_rounded,
            title: 'Brak treningów',
            text: 'Zapisuj treningi, a zobaczysz tu historię i statystyki.'),
      ]);
    }
    final children = <Widget>[?header];
    String? month;
    for (final (i, t) in items.indexed) {
      final m = fmtMonthYear(t.date);
      if (m != month) {
        month = m;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Text(m, style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeSlideIn(
          index: i < 10 ? i : 0,
          child: K9Card(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            onTap: () => openTrainingForm(context, existing: t),
            child: ListRow(
              icon: t.discipline.icon,
              color: t.discipline.color,
              title: t.notes.isEmpty ? t.discipline.label : '${t.discipline.label} – ${t.notes}',
              subtitle: [
                '${fmtDateShort(t.date)}, ${fmtTime(t.date)}',
                fmtDuration(t.durationMin),
                if (t.distanceKm != null) '${fmtKm(t.distanceKm!)} km',
                'RPE ${t.rpe}',
              ].join(' · '),
            ),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: children);
  }
}

class DisciplineScreen extends StatelessWidget {
  final Discipline discipline;
  const DisciplineScreen({super.key, required this.discipline});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
        Icon(discipline.icon, color: K9.orange),
        const SizedBox(width: 10),
        Text(discipline.label),
      ])),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openTrainingForm(context, discipline: discipline),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Trening', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final list = s.doneTrainings.where((t) => t.discipline == discipline).toList();
          final minutes = list.fold(0, (a, t) => a + t.durationMin);
          final km = list.fold(0.0, (a, t) => a + (t.distanceKm ?? 0));
          final avgRpe = list.isEmpty ? 0.0 : list.fold(0, (a, t) => a + t.rpe) / list.length;
          return TrainingHistoryList(
            items: list,
            header: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: K9Card(
                child: Row(children: [
                  Expanded(child: StatValue(label: 'Treningi', value: '${list.length}')),
                  Expanded(child: StatValue(label: 'Czas', value: fmtDurationShort(minutes))),
                  if (discipline.hasDistance)
                    Expanded(child: StatValue(label: 'Dystans', value: fmtKm(km), unit: 'km'))
                  else
                    Expanded(child: StatValue(label: 'Śr. RPE', value: fmtNum(avgRpe))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

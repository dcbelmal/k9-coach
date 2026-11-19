import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../gps/records.dart';
import 'calendar.dart';
import 'forms.dart';
import 'stats.dart';
import 'track_detail.dart';
import 'training_start.dart';
import 'gps_screen.dart';
import '../dogs/dog_profiles.dart';
import '../l10n/l10n.dart';

/// Który segment zakładki Trening jest otwarty (0 dyscypliny … 3 statystyki).
final trainingTab = ValueNotifier<int>(0);

class TrainingScreen extends StatefulWidget {
  final int initialTab;

  /// Pokazywany jako zakładka dolnego paska (bez przycisku wstecz i bez własnego „+”).
  final bool inTab;
  const TrainingScreen({super.key, this.initialTab = 0, this.inTab = false});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late int tab = widget.inTab ? trainingTab.value : widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (widget.inTab) trainingTab.addListener(_sync);
  }

  @override
  void dispose() {
    trainingTab.removeListener(_sync);
    super.dispose();
  }

  void _sync() => setState(() => tab = trainingTab.value);

  void _select(int i) {
    if (widget.inTab) {
      trainingTab.value = i;
    } else {
      setState(() => tab = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Trening')),
        automaticallyImplyLeading: !widget.inTab,
        actions: [
          TextButton.icon(
            onPressed: () => openCalendar(context),
            icon: const Icon(Icons.calendar_month_outlined, color: K9.orange),
            label: Text(tr('Kalendarz'), style: TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: widget.inTab || tab == 3
          ? null
          : FloatingActionButton(
              backgroundColor: K9.orange,
              foregroundColor: Colors.black,
              onPressed: () => openTrainingForm(context, planned: tab == 1),
              child: const Icon(Icons.add_rounded, size: 30),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Segmented(
              items: [tr('Dyscypliny'), tr('Plan'), tr('Historia'), tr('Statystyki')],
              index: tab,
              onChanged: _select),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (tab) {
              0 => const _Disciplines(key: ValueKey(0)),
              1 => const WeekPlan(key: ValueKey(1)),
              2 => const _History(key: ValueKey(2)),
              _ => const StatsScreen(key: ValueKey(3), embedded: true),
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
        key: PageStorageKey('training-disc-${DogProfiles.instance.activeId}'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          const StartTrainingButton(),
          const SizedBox(height: 10),
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
        height: 86,
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
                      Text(d.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 12.5)),
                      Text(
                          last == null
                              ? tr('Brak treningów')
                              : tr('{0} treningów · ostatni {1}', [list.length, relDays(last.date)]),
                          style: const TextStyle(color: K9.muted, fontSize: 11.5)),
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
  // Oglądany tydzień przetrwa zmianę zakładki (PageStorage), osobno dla psa.
  String get _id => 'plan-week-${DogProfiles.instance.activeId}';
  late DateTime _week =
      PageStorage.maybeOf(context)?.readState(context, identifier: _id) as DateTime? ?? startOfWeek(DateTime.now());
  DateTime get week => _week;
  set week(DateTime v) {
    _week = v;
    PageStorage.maybeOf(context)?.writeState(context, v, identifier: _id);
  }

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
      builder: (context, _) => ListView(
          key: PageStorageKey('training-plan-${DogProfiles.instance.activeId}'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
        Row(children: [
          IconButton(tooltip: tr('Poprzedni'), 
              onPressed: () => setState(() => week = week.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left_rounded, color: K9.orange)),
          Expanded(
            child: Column(children: [
              Text(tr('Tydzień {0}', [_weekNumber(week)]),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${fmtDateShort(week)} – ${fmtDateShort(week.add(const Duration(days: 6)))}',
                  style: const TextStyle(color: K9.muted, fontSize: 12.5)),
            ]),
          ),
          IconButton(tooltip: tr('Następny'), 
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
                child: Row(children: [
                  Icon(Icons.add_rounded, color: K9.faint, size: 20),
                  SizedBox(width: 8),
                  Text(tr('Dodaj trening'), style: TextStyle(color: K9.faint)),
                ]),
              ),
            for (final t in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: K9Card(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  onTap: () => openTraining(context, t),
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
                    if (!t.done && !dayOnly(t.date).isBefore(dayOnly(DateTime.now())))
                      IconButton(
                        tooltip: tr('Rozpocznij trening'),
                        onPressed: () => openGps(context, plan: t),
                        icon: const Icon(Icons.play_circle_fill_rounded, color: K9.orange, size: 30),
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

class _History extends StatefulWidget {
  const _History({super.key});

  @override
  State<_History> createState() => _HistoryState();
}

/// Historia z filtrem dyscypliny (pokazujemy tylko dyscypliny, które są w historii).
class _HistoryState extends State<_History> {
  // Wybrany filtr przetrwa zmianę zakładki (PageStorage), osobno dla psa.
  String get _id => 'history-filter-${DogProfiles.instance.activeId}';
  late Discipline? _filter = PageStorage.maybeOf(context)?.readState(context, identifier: _id) as Discipline?;
  Discipline? get filter => _filter;
  set filter(Discipline? v) {
    _filter = v;
    PageStorage.maybeOf(context)?.writeState(context, v, identifier: _id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final all = s.doneTrainings.toList();
        final present = [for (final d in Discipline.values) if (all.any((t) => t.discipline == d)) d];
        final f = present.contains(filter) ? filter : null;
        Widget chip(String label, Discipline? d) {
          final sel = f == d;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              avatar: d == null ? null : Icon(d.icon, size: 18, color: sel ? Colors.black : d.color),
              selected: sel,
              showCheckmark: false,
              selectedColor: K9.orange,
              backgroundColor: K9.cardHi,
              side: BorderSide.none,
              labelStyle: TextStyle(color: sel ? Colors.black : K9.text, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (_) => setState(() => filter = d),
            ),
          );
        }

        final header = present.length < 2
            ? null
            : SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  children: [chip(tr('Wszystkie'), null), for (final d in present) chip(d.label, d)],
                ),
              );
        return TrainingHistoryList(
          items: f == null ? all : all.where((t) => t.discipline == f).toList(),
          header: header,
          storageKey: PageStorageKey('training-history-${DogProfiles.instance.activeId}-${f?.name}'),
        );
      },
    );
  }
}

class TrainingHistoryList extends StatelessWidget {
  final List<TrainingSession> items;
  final Widget? header;
  /// Klucz do zapamiętania pozycji przewijania (np. przy zmianie zakładek).
  final Key? storageKey;
  const TrainingHistoryList({super.key, required this.items, this.header, this.storageKey});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(children: [
        ?header,
        EmptyState(
            icon: Icons.directions_run_rounded,
            title: tr('Brak treningów'),
            text: tr('Zapisuj treningi, a zobaczysz tu historię i statystyki.')),
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
            onTap: () => openTraining(context, t),
            child: ListRow(
              icon: t.discipline.icon,
              color: t.discipline.color,
              title: t.notes.isEmpty ? t.discipline.label : '${t.discipline.label} – ${t.notes}',
              trailing: t.hasTrack ? const Icon(Icons.route_rounded, color: K9.orange, size: 20) : null,
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
    return ListView(
        key: storageKey, padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: children);
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
        onPressed: () => discipline.hasDistance
            ? openGps(context, discipline: discipline)
            : openTrainingForm(context, discipline: discipline),
        icon: Icon(discipline.hasDistance ? Icons.play_arrow_rounded : Icons.add_rounded),
        label: Text(discipline.hasDistance ? tr('Start GPS') : tr('Trening'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
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
              child: Column(children: [
                if (discipline.hasDistance) ...[
                  Row(children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => openTrainingForm(context, discipline: discipline),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: Text(tr('Dodaj ręcznie')),
                    ),
                  ]),
                ],
                K9Card(
                child: Row(children: [
                  Expanded(child: StatValue(label: tr('Treningi'), value: '${list.length}')),
                  Expanded(child: StatValue(label: tr('Czas'), value: fmtDurationShort(minutes))),
                  if (discipline.hasDistance)
                    Expanded(child: StatValue(label: tr('Dystans'), value: fmtKm(km), unit: 'km'))
                  else
                    Expanded(child: StatValue(label: tr('Śr. RPE'), value: fmtNum(avgRpe))),
                ]),
              ),
                if (discipline.hasDistance && !Records.of(list, discipline).isEmpty) ...[
                  gap12,
                  RecordsCard(records: Records.of(list, discipline)),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

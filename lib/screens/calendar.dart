import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forms.dart';
import 'home.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = dayOnly(DateTime.now());

  static const _weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sob', 'Nd'];

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final first = DateTime(month.year, month.month, 1);
        final next = DateTime(month.year, month.month + 1, 1);
        final daysInMonth = next.difference(first).inDays;
        final offset = first.weekday - 1;
        final monthItems = s.agendaBetween(first, next);
        final byDay = <int, List<AgendaItem>>{};
        for (final i in monthItems) {
          byDay.putIfAbsent(i.date.day, () => []).add(i);
        }
        final dayItems = s.agendaFor(selected);

        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
            Row(children: [
              const Icon(Icons.calendar_month_rounded, color: K9.orange),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Kalendarz', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
              IconButton(
                onPressed: () => openEventForm(context, date: selected),
                icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange, size: 28),
              ),
            ]),
            gap12,
            K9Card(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Column(children: [
                Row(children: [
                  IconButton(
                      onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
                      icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(fmtMonthYear(month),
                          key: ValueKey(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                      onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
                      icon: const Icon(Icons.chevron_right_rounded)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  for (final w in _weekdays)
                    Expanded(
                        child: Center(
                            child: Text(w,
                                style: const TextStyle(
                                    color: K9.muted, fontSize: 12, fontWeight: FontWeight.w600)))),
                ]),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: offset + daysInMonth,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, childAspectRatio: 1.05),
                  itemBuilder: (context, i) {
                    if (i < offset) return const SizedBox();
                    final day = i - offset + 1;
                    final date = DateTime(month.year, month.month, day);
                    final isSel = sameDay(date, selected);
                    final isToday = sameDay(date, DateTime.now());
                    final dots = (byDay[day] ?? []).take(3).toList();
                    return GestureDetector(
                      onTap: () => setState(() => selected = date),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: isSel ? K9.orangeGradient : null,
                          shape: BoxShape.circle,
                          border: isToday && !isSel ? Border.all(color: K9.orange, width: 1.4) : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('$day',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.black : (date.weekday >= 6 ? K9.muted : K9.text))),
                          const SizedBox(height: 3),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (final d in dots)
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                    color: isSel ? Colors.black : dotColor(d), shape: BoxShape.circle),
                              ),
                            if (dots.isEmpty) const SizedBox(height: 5),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
              ]),
            ),
            gap16,
            Row(children: [
              Expanded(
                child: Text(
                    sameDay(selected, DateTime.now()) ? 'Dziś, ${fmtDate(selected)}' : fmtDate(selected),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => _addFor(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Dodaj'),
              ),
            ]),
            const SizedBox(height: 4),
            if (dayItems.isEmpty)
              const K9Card(
                child: Text('Brak wpisów w tym dniu.', style: TextStyle(color: K9.muted)),
              ),
            for (final (i, it) in dayItems.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn(
                  key: ValueKey('${selected.toIso8601String()}-$i'),
                  index: i,
                  child: K9Card(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    onTap: () => openAgendaItem(context, it),
                    child: ListRow(
                      icon: it.icon,
                      color: it.color,
                      title: it.title,
                      subtitle: it.source is HealthRecord
                          ? '${it.subtitle} · termin'
                          : '${fmtTime(it.date)} · ${it.subtitle}',
                    ),
                  ),
                ),
              ),
            gap12,
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (final (label, color) in [
                ('Trening', K9.orange),
                ('Zdrowie', K9.green),
                ('Zawody / wystawy', K9.yellow),
                ('Wizyta', K9.red),
                ('Przypomnienie', K9.blue),
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(color: K9.muted, fontSize: 12)),
                ]),
            ]),
          ]),
        );
      },
    );
  }

  void _addFor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListRow(
              icon: Icons.directions_run_rounded,
              color: K9.orange,
              title: 'Trening',
              onTap: () {
                Navigator.pop(c);
                openTrainingForm(context,
                    planned: selected.isAfter(DateTime.now()),
                    date: DateTime(selected.year, selected.month, selected.day, 17));
              }),
          ListRow(
              icon: Icons.event_rounded,
              color: K9.yellow,
              title: 'Zawody, wystawa, wizyta lub przypomnienie',
              onTap: () {
                Navigator.pop(c);
                openEventForm(context, date: selected);
              }),
          ListRow(
              icon: Icons.vaccines_rounded,
              color: K9.green,
              title: 'Wpis zdrowotny',
              onTap: () {
                Navigator.pop(c);
                openHealthForm(context);
              }),
        ]),
      ),
    );
  }
}

Color dotColor(AgendaItem i) => switch (i.source) {
      TrainingSession _ => K9.orange,
      HealthRecord _ => K9.green,
      CalendarEvent e => switch (e.type) {
          EventType.competition || EventType.show => K9.yellow,
          EventType.vet => K9.red,
          _ => K9.blue,
        },
      _ => K9.muted,
    };

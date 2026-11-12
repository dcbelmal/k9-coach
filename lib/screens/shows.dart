import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../champ_rules.dart';
import '../models_ext.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'zkwp_calendar.dart';

final _s = AppStore.instance;

class ShowsScreen extends StatefulWidget {
  final int initialTab;
  const ShowsScreen({super.key, this.initialTab = 0});
  @override
  State<ShowsScreen> createState() => _ShowsScreenState();
}

class _ShowsScreenState extends State<ShowsScreen> {
  late int tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Row(children: [
        Icon(Icons.emoji_events_outlined, color: K9.orange),
        SizedBox(width: 10),
        Text('Wystawy'),
      ])),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openShowForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Segmented(
              items: const ['Terminarz', 'Moje', 'Wyniki', 'Tytuły'], index: tab, onChanged: (i) => setState(() => tab = i)),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _s,
            builder: (context, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (tab) {
                0 => const ZkwpCalendar(key: ValueKey(0)),
                1 => const _ShowList(key: ValueKey(1)),
                2 => const _Results(key: ValueKey(2)),
                _ => const _Titles(key: ValueKey(3)),
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _ShowList extends StatelessWidget {
  const _ShowList({super.key});

  @override
  Widget build(BuildContext context) {
    final now = dayOnly(DateTime.now());
    final upcoming = _s.shows.where((e) => !e.date.isBefore(now)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = _s.shows.where((e) => e.date.isBefore(now)).toList();
    if (_s.shows.isEmpty) {
      return EmptyState(
        icon: Icons.emoji_events_rounded,
        title: 'Brak wystaw',
        text: 'Dodaj wystawę, a przypomnę o terminie zgłoszeń i samej wystawie.',
        action: 'Dodaj wystawę',
        onAction: () => openShowForm(context),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
      if (upcoming.isNotEmpty) const _Header('Nadchodzące'),
      for (final (i, e) in upcoming.indexed) FadeSlideIn(index: i, child: _ShowCard(e: e)),
      if (past.isNotEmpty) const _Header('Minione'),
      for (final (i, e) in past.indexed) FadeSlideIn(index: i + upcoming.length, child: _ShowCard(e: e)),
    ]);
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(text, style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
      );
}

class _ShowCard extends StatelessWidget {
  final ShowEntry e;
  const _ShowCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final upcoming = !e.date.isBefore(dayOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: K9Card(
        onTap: () => openShowForm(context, existing: e),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DateBadge(date: e.date),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(
                    [if (e.place.isNotEmpty) e.place, e.type.label, 'kl. ${e.showClass.label}'].join(' · '),
                    style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              ]),
            ),
            _StatusChip(status: e.status),
          ]),
          if (upcoming && e.entryDeadline != null && e.status == ShowStatus.planned) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.assignment_late_outlined, size: 16, color: K9.yellow),
              const SizedBox(width: 6),
              Text('Zgłoszenia do ${fmtDate(e.entryDeadline!)} (${relDays(e.entryDeadline!)})',
                  style: const TextStyle(color: K9.yellow, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ],
          if (e.hasResult) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (e.grade != null) _Tag(e.grade!, K9.green),
              if (e.placement != null) _Tag('${e.placement}. lokata', K9.blue),
              for (final t in e.titles) _Tag(t.short, t.color),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final DateTime date;
  const _DateBadge({required this.date});
  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: K9.orange.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text('${date.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: K9.orange)),
          Text(fmtDateShort(date).split(' ').last, style: const TextStyle(fontSize: 11, color: K9.orange)),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  final ShowStatus status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) => _Tag(status.label, status.color);
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
      );
}

class _Results extends StatelessWidget {
  const _Results({super.key});

  @override
  Widget build(BuildContext context) {
    final list = _s.shows.where((e) => e.hasResult).toList();
    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.military_tech_rounded,
          title: 'Brak wyników',
          text: 'Po wystawie otwórz ją i wpisz ocenę, lokatę i zdobyte tytuły.');
    }
    final excellent = list.where((e) => e.grade == 'Doskonała').length;
    final wins = list.where((e) => e.placement == 1).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
      K9Card(
        child: Row(children: [
          Expanded(child: StatValue(label: 'Wystawy', value: '${list.length}')),
          Expanded(child: StatValue(label: 'Oceny doskonałe', value: '$excellent')),
          Expanded(child: StatValue(label: 'Pierwsze lokaty', value: '$wins')),
        ]),
      ),
      gap12,
      for (final (i, e) in list.indexed) FadeSlideIn(index: i, child: _ShowCard(e: e)),
    ]);
  }
}

class _Titles extends StatelessWidget {
  const _Titles({super.key});

  @override
  Widget build(BuildContext context) {
    final medals = <(ShowTitle, ShowEntry)>[
      for (final e in _s.shows)
        for (final t in e.titles) (t, e)
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
      K9Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Championaty', icon: Icons.workspace_premium_outlined),
          for (final c in Championship.values) ...[
            _ChampRow(st: _s.champStatus(c)),
            const SizedBox(height: 14),
          ],
          const Text(
              'Zasady wg regulaminów ZKwP (zkwp.pl/championaty) i FCI. Stuknij championat, aby zobaczyć warunki. Tytuł zatwierdza ZKwP na wniosek właściciela.',
              style: TextStyle(color: K9.faint, fontSize: 11.5)),
        ]),
      ),
      gap16,
      const SectionTitle('Galeria medali', icon: Icons.military_tech_outlined),
      if (medals.isEmpty)
        const K9Card(child: Text('Tu pojawią się zdobyte tytuły.', style: TextStyle(color: K9.muted)))
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
          children: [
            for (final (i, m) in medals.indexed)
              FadeSlideIn(
                index: i,
                child: K9Card(
                  padding: const EdgeInsets.all(10),
                  onTap: () => openShowForm(context, existing: m.$2),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Medal(title: m.$1),
                    const SizedBox(height: 8),
                    Text(m.$1.short,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), textAlign: TextAlign.center),
                    Text(m.$2.place.isEmpty ? fmtDateShort(m.$2.date) : m.$2.place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: K9.muted, fontSize: 11)),
                    Text(fmtDate(m.$2.date), style: const TextStyle(color: K9.faint, fontSize: 10.5)),
                  ]),
                ),
              ),
          ],
        ),
    ]);
  }
}

class _ChampRow extends StatelessWidget {
  final ChampStatus st;
  const _ChampRow({required this.st});

  @override
  Widget build(BuildContext context) {
    final done = st.achieved;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRules(context, st),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: done ? K9.green : K9.faint, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(st.champ.label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(st.summary, style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          const Icon(Icons.chevron_right_rounded, color: K9.faint, size: 18),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: done ? 1 : st.progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 7,
                backgroundColor: K9.cardHi,
                valueColor: AlwaysStoppedAnimation(done ? K9.green : K9.orange),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

void _showRules(BuildContext context, ChampStatus st) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.viewPaddingOf(c).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetTitle(st.champ.label),
        for (final r in st.reqs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.ok ? Icons.check_circle_rounded : Icons.cancel_outlined,
                  color: r.ok ? K9.green : K9.faint, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(r.text, style: const TextStyle(fontSize: 14.5))),
            ]),
          ),
        gap16,
        K9Card(
          color: K9.cardHi,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Zasada', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(st.rule, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13.5, height: 1.4)),
          ]),
        ),
        if (st.champ == Championship.inter) ...[
          gap12,
          const Text(
              'Rasy z grup I–III domyślnie traktuję jako podlegające próbom pracy. Możesz to zmienić w profilu psa. Zdaną próbę zaznacz w Celach (np. IGP 1 – zaliczone).',
              style: TextStyle(color: K9.faint, fontSize: 12)),
        ],
      ]),
    ),
  );
}

class _Medal extends StatelessWidget {
  final ShowTitle title;
  const _Medal({required this.title});
  @override
  Widget build(BuildContext context) => Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [title.color, title.color.withValues(alpha: 0.35)]),
          boxShadow: [BoxShadow(color: title.color.withValues(alpha: 0.35), blurRadius: 14)],
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
        ),
        child: const Icon(Icons.emoji_events_rounded, color: Colors.black87, size: 28),
      );
}

// ---------------------------------------------------------------------------
// Formularz wystawy
// ---------------------------------------------------------------------------

Future<void> openShowForm(BuildContext context, {ShowEntry? existing, DateTime? date}) =>
    showFormSheet(context, _ShowForm(existing: existing, date: date));

class _ShowForm extends StatefulWidget {
  final ShowEntry? existing;
  final DateTime? date;
  const _ShowForm({this.existing, this.date});
  @override
  State<_ShowForm> createState() => _ShowFormState();
}

class _ShowFormState extends State<_ShowForm> {
  late final e = widget.existing == null
      ? ShowEntry(id: newId(), name: '', date: widget.date ?? dayOnly(DateTime.now()).add(const Duration(days: 30, hours: 9)))
      : ShowEntry.fromJson(widget.existing!.toJson());
  late final name = TextEditingController(text: e.name);
  late final place = TextEditingController(text: e.place);
  late final judge = TextEditingController(text: e.judge);
  late final fee = TextEditingController(text: e.fee == null ? '' : fmtNum(e.fee!, 0));
  late final placement = TextEditingController(text: e.placement?.toString() ?? '');
  late final notes = TextEditingController(text: e.notes);
  late final country = TextEditingController(text: e.country);

  Widget _chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> on) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              showCheckmark: false,
              selectedColor: K9.orange,
              backgroundColor: K9.cardHi,
              side: BorderSide.none,
              labelStyle: TextStyle(color: v == selected ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (_) => setState(() => on(v)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final past = e.date.isBefore(DateTime.now().add(const Duration(days: 1)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? 'Nowa wystawa' : 'Wystawa',
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'wystawę')) {
                    await _s.deleteShow(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Nazwa wystawy *')),
      gap12,
      Row(children: [
        Expanded(child: TextField(controller: place, decoration: const InputDecoration(labelText: 'Miejsce'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: judge, decoration: const InputDecoration(labelText: 'Sędzia'))),
      ]),
      gap12,
      DateField(label: 'Data wystawy', value: e.date, withTime: true, onChanged: (d) => setState(() => e.date = d!)),
      if (e.type == ShowType.international) ...[
        gap12,
        TextField(controller: country, decoration: const InputDecoration(labelText: 'Kraj (ważne dla C.I.B.)')),
      ],
      gap16,
      const Text('Rodzaj', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _chips(ShowType.values, e.type, (v) => v.label, (v) => e.type = v),
      gap16,
      const Text('Klasa', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _chips(ShowClass.values, e.showClass, (v) => v.label, (v) => e.showClass = v),
      gap16,
      const Text('Zgłoszenie', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _chips(ShowStatus.values, e.status, (v) => v.label, (v) => e.status = v),
      gap12,
      Row(children: [
        Expanded(
          flex: 3,
          child: DateField(
              label: 'Termin zgłoszeń',
              value: e.entryDeadline,
              clearable: true,
              onChanged: (d) => setState(() => e.entryDeadline = d)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextField(
              controller: fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Opłata (zł)')),
        ),
      ]),
      if (past || e.hasResult) ...[
        const SizedBox(height: 22),
        const Text('Wynik', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        gap12,
        Row(children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String?>(
              initialValue: e.grade,
              dropdownColor: K9.cardHi,
              decoration: const InputDecoration(labelText: 'Ocena'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final g in showGrades) DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => e.grade = v,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
                controller: placement,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lokata')),
          ),
        ]),
        gap12,
        const Text('Zdobyte tytuły', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in ShowTitle.values.where((t) => t != ShowTitle.jcwc || e.titles.contains(t)))
            FilterChip(
              label: Text(t.label),
              selected: e.titles.contains(t),
              showCheckmark: false,
              selectedColor: t.color,
              backgroundColor: K9.cardHi,
              side: BorderSide.none,
              labelStyle: TextStyle(
                  color: e.titles.contains(t) ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 12.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => setState(() => v ? e.titles.add(t) : e.titles.remove(t)),
            ),
        ]),
      ],
      gap16,
      TextField(controller: notes, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Notatki (opis sędziego, wrażenia)')),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (name.text.trim().isEmpty) {
            toast(context, 'Wpisz nazwę wystawy');
            return;
          }
          e
            ..name = name.text.trim()
            ..place = place.text.trim()
            ..judge = judge.text.trim()
            ..country = country.text.trim().isEmpty ? 'Polska' : country.text.trim()
            ..fee = parseNum(fee.text)
            ..placement = int.tryParse(placement.text.trim())
            ..notes = notes.text.trim();
          if (e.hasResult && e.status != ShowStatus.cancelled) e.status = ShowStatus.done;
          await _s.upsertShow(e);
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, 'Zapisano');
          }
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

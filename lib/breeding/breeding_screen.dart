import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'breeding_logic.dart';
import 'breeding_models.dart';
import 'breeding_store.dart';
import 'litter_screen.dart';

void openBreeding(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BreedingScreen()));

String _countdown(int days) {
  if (days == 0) return 'dziś';
  if (days == 1) return 'jutro';
  if (days > 0) return 'za $days dni';
  return '${-days} dni temu';
}

/// Moduł hodowlany: krycia, ciąża, mioty.
class BreedingScreen extends StatelessWidget {
  const BreedingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = BreedingStore.instance;
    final dog = AppStore.instance.dog!;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.child_friendly_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text('Moduł hodowlany'),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openMatingForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Dodaj krycie', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: b,
        builder: (context, _) {
          final active = dog.female ? b.active : null;
          final now = DateTime.now();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            if (active != null) ...[
              FadeSlideIn(child: _PregnancyCard(m: active)),
              gap12,
              FadeSlideIn(index: 1, child: _StatusButtons(m: active)),
              gap12,
              FadeSlideIn(index: 2, child: _Timeline(m: active, now: now)),
            ] else if (dog.female)
              const FadeSlideIn(child: _Calculator())
            else
              FadeSlideIn(child: _StudSummary(matings: b.matings)),
            if (b.litters.isNotEmpty) ...[
              gap12,
              FadeSlideIn(index: 3, child: _Litters(items: b.litters)),
            ],
            gap12,
            FadeSlideIn(index: 4, child: _History(items: b.matings, female: dog.female)),
            if (dog.female) ...[
              gap12,
              K9Card(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: b.remind,
                  onChanged: b.setRemind,
                  title: const Text('Powiadomienia o ciąży'),
                  subtitle: const Text('USG, RTG, kojec, temperatura i termin porodu',
                      style: TextStyle(color: K9.muted, fontSize: 12.5)),
                ),
              ),
            ],
            gap12,
            const Text(
              'Terminy są orientacyjne. Przebieg ciąży i porodu konsultuj z weterynarzem.',
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ]);
        },
      ),
    );
  }
}

class _PregnancyCard extends StatelessWidget {
  final Mating m;
  const _PregnancyCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final day = PregnancyCalc.dayOf(m, now);
    final left = PregnancyCalc.daysToDue(m, now);
    final (from, to) = PregnancyCalc.window(m);
    final c = m.status.color;
    return K9Card(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A1A0C), K9.card],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RingGauge(
            value: (day / PregnancyCalc.typical).clamp(0.0, 1.0),
            size: 96,
            stroke: 9,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$day', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
              const Text('dzień', style: TextStyle(color: K9.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(child: Text(m.status.label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
              const SizedBox(height: 6),
              Text('${PregnancyCalc.weekLabel(day)} ciąży', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(m.partner.isEmpty ? 'Krycie ${fmtDate(m.first)}' : 'Reproduktor: ${m.partner}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: K9.muted, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: StatValue(
              label: 'Przewidywany poród',
              value: fmtDateShort(PregnancyCalc.due(m)),
            ),
          ),
          Expanded(
            child: StatValue(
              label: 'Do porodu',
              value: left >= 0 ? '$left' : 'po terminie',
              unit: left >= 0 ? 'dni' : null,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          'Okno porodu: ${fmtDateShort(from)} – ${fmtDateShort(to)}'
          '${m.ovulation != null ? ' (liczone od owulacji)' : ''}',
          style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13),
        ),
      ]),
    );
  }
}

class _StatusButtons extends StatelessWidget {
  final Mating m;
  const _StatusButtons({required this.m});

  @override
  Widget build(BuildContext context) {
    final b = BreedingStore.instance;
    final day = PregnancyCalc.dayOf(m, DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (day >= 50)
        FilledButton.icon(
          onPressed: () => openLitterForm(context, m),
          icon: const Icon(Icons.celebration_rounded),
          label: const Text('Poród – zapisz miot'),
        ),
      if (m.status == PregnancyStatus.waiting) ...[
        if (day >= 50) const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => b.setStatus(m, PregnancyStatus.confirmed),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Potwierdzona'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await b.setStatus(m, PregnancyStatus.notPregnant);
                if (context.mounted) toast(context, 'Zapisano: suka nie zaszła w ciążę');
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Nie zaszła'),
            ),
          ),
        ]),
      ] else if (day < 50)
        OutlinedButton.icon(
          onPressed: () => openLitterForm(context, m),
          icon: const Icon(Icons.celebration_rounded),
          label: const Text('Poród – zapisz miot'),
        ),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  final Mating m;
  final DateTime now;
  const _Timeline({required this.m, required this.now});

  @override
  Widget build(BuildContext context) {
    final next = PregnancyCalc.next(m, now);
    final today = dayOnly(now);
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Kalendarz ciąży', icon: Icons.timeline_rounded),
        for (final (i, ms) in PregnancyCalc.milestones.indexed)
          _milestoneRow(ms, PregnancyCalc.milestoneDate(m, ms), today, ms == next, i == PregnancyCalc.milestones.length - 1),
      ]),
    );
  }

  Widget _milestoneRow(PregnancyMilestone ms, DateTime date, DateTime today, bool isNext, bool last) {
    final done = date.isBefore(today);
    final color = isNext ? K9.orange : (done ? K9.green : K9.faint);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            const SizedBox(height: 3),
            Icon(done ? Icons.check_circle_rounded : (isNext ? Icons.radio_button_checked_rounded : Icons.circle_outlined),
                size: 18, color: color),
            if (!last) Expanded(child: Container(width: 2, color: K9.border)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(ms.title,
                      style: TextStyle(fontWeight: FontWeight.w700, color: done && !isNext ? K9.muted : K9.text)),
                ),
                Text('${ms.day == 0 ? 'dzień 0' : '${ms.day}. dzień'} · ${fmtDateShort(date)}',
                    style: TextStyle(color: isNext ? K9.orange : K9.muted, fontSize: 12)),
              ]),
              if (isNext || !done) ...[
                const SizedBox(height: 3),
                Text(ms.text, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
              ],
              if (isNext)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_countdown(date.difference(today).inDays),
                      style: const TextStyle(color: K9.orange, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Kalkulator ciąży (bez zapisu) – gdy nie ma trwającej ciąży.
class _Calculator extends StatefulWidget {
  const _Calculator();
  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  DateTime mating = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final m = Mating(id: 'calc', dates: [mating]);
    final (from, to) = PregnancyCalc.window(m);
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Kalkulator ciąży', icon: Icons.calculate_outlined),
        DateField(label: 'Data krycia', value: mating, onChanged: (v) => setState(() => mating = v!)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatValue(label: 'Przewidywany poród', value: fmtDateShort(PregnancyCalc.due(m)))),
          Expanded(child: StatValue(label: 'Okno porodu', value: '${fmtDateShort(from)} – ${fmtDateShort(to)}')),
        ]),
        const SizedBox(height: 10),
        Text('USG: ${fmtDateShort(mating.add(const Duration(days: 25)))} – ${fmtDateShort(mating.add(const Duration(days: 30)))}'
            ' · RTG: od ${fmtDateShort(mating.add(const Duration(days: 45)))}',
            style: const TextStyle(color: K9.muted, fontSize: 13)),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => openMatingForm(context, date: mating),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Zapisz to krycie'),
        ),
      ]),
    );
  }
}

class _StudSummary extends StatelessWidget {
  final List<Mating> matings;
  const _StudSummary({required this.matings});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final thisYear = matings.where((m) => m.first.year == year).length;
    final puppies = matings.fold(0, (a, m) => a + (m.litter?.puppies.length ?? 0));
    return K9Card(
      child: Row(children: [
        Expanded(child: StatValue(label: 'Krycia razem', value: '${matings.length}')),
        Expanded(child: StatValue(label: 'W tym roku', value: '$thisYear')),
        Expanded(child: StatValue(label: 'Szczenięta', value: '$puppies')),
      ]),
    );
  }
}

class _Litters extends StatelessWidget {
  final List<Mating> items;
  const _Litters({required this.items});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Mioty', icon: Icons.pets_rounded),
        for (final m in items)
          ListRow(
            icon: Icons.child_care_rounded,
            color: K9.blue,
            title: 'Miot ${fmtDate(m.litter!.born)}',
            subtitle: [
              '${m.litter!.puppies.length} szczeniąt (${m.litter!.males} ps., ${m.litter!.females} s.)',
              _age(m.litter!.ageDays(now)),
              if (m.litter!.puppies.any((p) => p.losing)) 'spadek wagi!',
            ].join(' · '),
            onTap: () => openLitter(context, m),
          ),
      ]),
    );
  }

  String _age(int d) => d < 14 ? '$d dni' : (d < 70 ? '${d ~/ 7} tyg.' : '${(d / 30.4).floor()} mies.');
}

class _History extends StatelessWidget {
  final List<Mating> items;
  final bool female;
  const _History({required this.items, required this.female});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Rejestr kryć', icon: Icons.history_rounded),
        if (items.isEmpty)
          Text(female ? 'Brak wpisów. Dodaj krycie, a policzę termin porodu.' : 'Brak wpisów. Zapisz kryte suki i mioty.',
              style: const TextStyle(color: K9.muted)),
        for (final m in items)
          ListRow(
            icon: Icons.favorite_rounded,
            color: female ? m.status.color : K9.orange,
            title: '${fmtDate(m.first)}${m.dates.length > 1 ? ' (+${m.dates.length - 1})' : ''}',
            subtitle: [
              if (m.partner.isNotEmpty) m.partner,
              if (female) m.status.label,
              if (m.method == MatingMethod.ai) 'inseminacja',
            ].join(' · '),
            onTap: () => openMatingForm(context, existing: m),
          ),
      ]),
    );
  }
}

/// Karta na ekranie Start – tylko w trakcie ciąży.
class PregnancyHomeCard extends StatelessWidget {
  const PregnancyHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BreedingStore.instance,
      builder: (context, _) {
        final m = BreedingStore.instance.active;
        if (m == null) return const SizedBox.shrink();
        final now = DateTime.now();
        final day = PregnancyCalc.dayOf(m, now);
        final left = PregnancyCalc.daysToDue(m, now);
        final next = PregnancyCalc.next(m, now);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: K9Card(
            onTap: () => openBreeding(context),
            child: Row(children: [
              RingGauge(
                value: (day / PregnancyCalc.typical).clamp(0.0, 1.0),
                size: 52,
                stroke: 6,
                center: Text('$day', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ciąża · ${PregnancyCalc.weekLabel(day)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    left >= 0
                        ? 'Poród ok. ${fmtDateShort(PregnancyCalc.due(m))} (${_countdown(left)})'
                        : 'Po terminie – skontaktuj się z weterynarzem',
                    style: const TextStyle(color: K9.muted, fontSize: 13),
                  ),
                  if (next != null && next.day != PregnancyCalc.typical)
                    Text('Dalej: ${next.title}', style: const TextStyle(color: K9.orange, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K9.faint),
            ]),
          ),
        );
      },
    );
  }
}

// --- Formularz krycia ---------------------------------------------------------

void openMatingForm(BuildContext context, {Mating? existing, DateTime? date}) =>
    showFormSheet(context, _MatingForm(existing: existing, date: date));

class _MatingForm extends StatefulWidget {
  final Mating? existing;
  final DateTime? date;
  const _MatingForm({this.existing, this.date});
  @override
  State<_MatingForm> createState() => _MatingFormState();
}

class _MatingFormState extends State<_MatingForm> {
  late DateTime first = widget.existing?.first ?? widget.date ?? dayOnly(DateTime.now());
  late DateTime? second = (widget.existing?.dates.length ?? 0) > 1 ? widget.existing!.dates[1] : null;
  late DateTime? ovulation = widget.existing?.ovulation;
  late MatingMethod method = widget.existing?.method ?? MatingMethod.natural;
  late final partner = TextEditingController(text: widget.existing?.partner ?? '');
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    final female = AppStore.instance.dog?.female ?? true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        e == null ? 'Nowe krycie' : 'Edytuj krycie',
        onDelete: e == null
            ? null
            : () async {
                if (await confirmDelete(context, 'krycie z ${fmtDate(e.first)}${e.litter != null ? ' (razem z miotem)' : ''}')) {
                  await BreedingStore.instance.delete(e);
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      DateField(label: 'Data krycia', value: first, onChanged: (v) => setState(() => first = v!)),
      gap12,
      DateField(
          label: 'Drugie krycie (opcjonalnie)', value: second, clearable: true, onChanged: (v) => setState(() => second = v)),
      gap12,
      TextField(
        controller: partner,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: female ? 'Reproduktor (imię i przydomek)' : 'Suka (imię i przydomek)'),
      ),
      gap12,
      SegmentedButton<MatingMethod>(
        segments: [for (final v in MatingMethod.values) ButtonSegment(value: v, label: Text(v.label))],
        selected: {method},
        onSelectionChanged: (s) => setState(() => method = s.first),
        showSelectedIcon: false,
      ),
      if (female) ...[
        gap12,
        DateField(
            label: 'Owulacja z badania progesteronu (opcjonalnie)',
            value: ovulation,
            clearable: true,
            onChanged: (v) => setState(() => ovulation = v)),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 6),
          child: Text('Jeśli znasz dzień owulacji, termin porodu będzie dokładniejszy (63 dni ± 1).',
              style: TextStyle(color: K9.faint, fontSize: 12)),
        ),
      ],
      gap12,
      TextField(
        controller: notes,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Notatki (progesteron, przebieg, badania)'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final dates = [first, ?second];
          if (second != null && second!.isBefore(first)) {
            toast(context, 'Drugie krycie nie może być przed pierwszym');
            return;
          }
          final m = Mating(
            id: e?.id ?? newId(),
            dates: dates,
            partner: partner.text.trim(),
            method: method,
            ovulation: ovulation,
            notes: notes.text.trim(),
            status: e?.status ?? PregnancyStatus.waiting,
            litter: e?.litter,
          );
          await BreedingStore.instance.upsert(m);
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'heat_logic.dart';
import 'heat_store.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

void openHeat(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HeatScreen()));

String _countdown(int days) {
  if (days == 0) return tr('dziś');
  if (days == 1) return 'jutro';
  if (days > 0) return tr('za {0} dni', [days]);
  return tr('{0} dni temu', [-days]);
}

/// Ekran modułu „Cykl i cieczka”.
class HeatScreen extends StatelessWidget {
  const HeatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final h = HeatStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.water_drop_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text(tr('Cykl i cieczka')),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openHeatForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Dodaj cieczkę'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: h,
        builder: (context, _) {
          final st = h.status;
          final now = DateTime.now();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            FadeSlideIn(child: _StageCard(st: st)),
            gap12,
            if (st.current != null)
              FadeSlideIn(
                index: 1,
                child: FilledButton.icon(
                  onPressed: () async {
                    final c = st.current!;
                    c.end = dayOnly(now);
                    await h.upsert(c);
                    if (context.mounted) toast(context, tr('Zapisano koniec cieczki'));
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(tr('Cieczka się skończyła (dziś)')),
                ),
              )
            else
              FadeSlideIn(
                index: 1,
                child: FilledButton.icon(
                  onPressed: () async {
                    await h.startToday();
                    if (context.mounted) toast(context, tr('Zapisano początek cieczki'));
                  },
                  icon: const Icon(Icons.water_drop_outlined),
                  label: Text(tr('Cieczka zaczęła się dziś')),
                ),
              ),
            gap12,
            FadeSlideIn(
              index: 2,
              child: K9Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionTitle(tr('Prognoza'), icon: Icons.event_repeat_rounded),
                  Row(children: [
                    Expanded(
                      child: StatValue(
                        label: tr('Kolejna cieczka'),
                        value: st.nextStart == null ? '—' : fmtDate(st.nextStart!),
                      ),
                    ),
                    Expanded(
                      child: StatValue(
                        label: tr('Odstęp'),
                        value: (st.intervalDays / 30.4).toStringAsFixed(1).replaceAll('.', ','),
                        unit: 'mies.',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    st.nextStart == null
                        ? tr('Zapisz pierwszą cieczkę, a policzę kolejną.')
                        : '${_countdown(st.daysToNext(now)!)} · ${tr('szacunkowo ±{0} dni', [st.nextSpreadDays])} · '
                            '${st.intervalFromHistory ? tr('średnia z Twoich wpisów ({0})', [st.gapsUsed]) : tr('bez historii przyjmuję ok. 6 miesięcy – u suk zwykle 5–12 mies.')}',
                    style: const TextStyle(color: K9.muted, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: h.remind,
                    onChanged: h.setRemind,
                    title: Text(tr('Powiadomienia')),
                    subtitle: Text(tr('Tydzień przed i w dniu orientacyjnego terminu, a w trakcie cieczki – przypomnienie o badaniach i zapisie końca'),
                        style: TextStyle(color: K9.muted, fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
            gap12,
            FadeSlideIn(index: 3, child: _History(cycles: h.cycles)),
            gap12,
            Text(
              tr('Prognozy są szacunkowe. Kalendarz nie wyznacza dni płodnych ani „bezpiecznych” dni – suka może zajść w ciążę w różnych dniach cieczki. Moment krycia ustala lekarz weterynarii na podstawie progesteronu i cytologii.'),
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ]);
        },
      ),
    );
  }
}

String _sourceLabel(HeatStatus st) => switch (st.source) {
      StageSource.ovulation => tr('Faza wg owulacji potwierdzonej przez lekarza.'),
      StageSource.cytology => tr('Faza wg ostatniej cytologii.'),
      StageSource.observation => tr('Faza wg Twojej obserwacji (suka przyjmuje psa) – szacunkowo.'),
      StageSource.calendar => tr('Szacunek z kalendarza – bez badań faza jest niepewna.'),
    };

class _StageCard extends StatelessWidget {
  final HeatStatus st;
  const _StageCard({required this.st});

  @override
  Widget build(BuildContext context) {
    final c = st.stage.color;
    final active = st.current != null;
    final day = st.day;
    final progress = active && day != null
        ? (day / st.typicalLengthDays).clamp(0.0, 1.0)
        : (st.nextStart != null && day != null ? (day / st.intervalDays).clamp(0.0, 1.0) : 0.0);
    return K9Card(
      child: Row(children: [
        RingGauge(
          value: progress,
          size: 88,
          stroke: 9,
          color: c,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(day == null || day < 1 ? '—' : '$day',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
            Text(tr('dzień'), style: TextStyle(color: K9.muted, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Aktualny etap'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(st.stage.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 4),
            Text(st.stage.description, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
            const SizedBox(height: 6),
            Text(_sourceLabel(st), style: const TextStyle(color: K9.faint, fontSize: 12)),
            if (active && st.fertileFrom != null) ...[
              const SizedBox(height: 4),
              Text(tr('Owulacja (wg lekarza): {0}. Największa płodność zwykle do ok. {1} – termin krycia ustal z lekarzem.', [fmtDate(st.fertileFrom!), fmtDate(st.fertileTo!)]),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _History extends StatelessWidget {
  final List<HeatCycle> cycles;
  const _History({required this.cycles});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Historia cykli'), icon: Icons.history_rounded),
        if (cycles.isEmpty)
          Text(tr('Brak wpisów.'), style: TextStyle(color: K9.muted)),
        for (final (i, c) in cycles.indexed)
          ListRow(
            icon: Icons.water_drop_rounded,
            color: K9.red,
            title: '${fmtDate(c.start)}${c.end == null ? tr(' – trwa') : ' – ${fmtDate(c.end!)}'}',
            subtitle: [
              if (c.lengthDays != null) '${c.lengthDays} dni',
              if (i + 1 < cycles.length)
                'odstęp ${dayOnly(c.start).difference(dayOnly(cycles[i + 1].start)).inCalDays} dni',
              if (c.ovulation != null) tr('owulacja {0}', [fmtDateShort(c.ovulation!)]),
              if (c.tests.isNotEmpty) tr('badania: {0}', [c.tests.length]),
              if (c.notes.isNotEmpty) c.notes,
            ].join(' · '),
            onTap: () => openHeatForm(context, existing: c),
          ),
      ]),
    );
  }
}

/// Karta na ekranie Start (tylko gdy moduł aktywny).
class HeatHomeCard extends StatelessWidget {
  const HeatHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final h = HeatStore.instance;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final st = h.status;
        final now = DateTime.now();
        final text = st.current != null
            ? tr('{0}. dzień cieczki · {1}', [st.day, st.stage.label])
            : st.nextStart == null
                ? tr('Zapisz początek cieczki, a przewidzę kolejną.')
                : tr('Kolejna cieczka orientacyjnie {0} ({1})', [_countdown(st.daysToNext(now)!), fmtDate(st.nextStart!)]);
        return K9Card(
          onTap: () => openHeat(context),
          child: Row(children: [
            IconBadge(Icons.water_drop_rounded, st.stage.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.current != null ? tr('Cieczka trwa') : (st.stage == HeatStage.unknown ? tr('Cykl i cieczka') : st.stage.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: K9.muted, fontSize: 13)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: K9.faint),
          ]),
        );
      },
    );
  }
}

void openHeatForm(BuildContext context, {HeatCycle? existing}) =>
    showFormSheet(context, _HeatForm(existing: existing));

class _HeatForm extends StatefulWidget {
  final HeatCycle? existing;
  const _HeatForm({this.existing});
  @override
  State<_HeatForm> createState() => _HeatFormState();
}

class _HeatFormState extends State<_HeatForm> {
  late DateTime start = widget.existing?.start ?? dayOnly(DateTime.now());
  late DateTime? end = widget.existing?.end;
  late DateTime? standing = widget.existing?.standingFrom;
  late DateTime? ovulation = widget.existing?.ovulation;
  late final Set<String> symptoms = {...?widget.existing?.symptoms};
  late final List<HeatTest> tests = [...?widget.existing?.tests];
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        e == null ? tr('Nowa cieczka') : tr('Edytuj cieczkę'),
        onDelete: e == null
            ? null
            : () async {
                if (await confirmDelete(context, tr('wpis cieczki'))) {
                  if (!context.mounted) return;
                  if (!await saveGuarded(context, () => HeatStore.instance.delete(e), done: tr('Usunięto'))) {
                    return;
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      DateField(label: tr('Początek (pierwszy dzień krwawienia)'), value: start, onChanged: (v) => setState(() => start = v!)),
      gap12,
      DateField(label: tr('Koniec (opcjonalnie)'), value: end, clearable: true, onChanged: (v) => setState(() => end = v)),
      gap16,
      Text(tr('Objawy'), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final sy in heatSymptoms)
          FilterChip(
            label: Text(tr(sy), style: const TextStyle(fontSize: 12.5)),
            selected: symptoms.contains(sy),
            onSelected: (v) => setState(() => v ? symptoms.add(sy) : symptoms.remove(sy)),
          ),
      ]),
      gap12,
      DateField(
          label: tr('Suka przyjmuje psa od (opcjonalnie)'),
          value: standing,
          clearable: true,
          onChanged: (v) => setState(() => standing = v)),
      gap12,
      DateField(
          label: tr('Owulacja potwierdzona przez lekarza (opcjonalnie)'),
          value: ovulation,
          clearable: true,
          onChanged: (v) => setState(() => ovulation = v)),
      gap16,
      Row(children: [
        Expanded(child: Text(tr('Badania'), style: const TextStyle(color: K9.muted, fontSize: 12.5))),
        TextButton.icon(
          onPressed: () => _addTest(HeatTestType.progesterone),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Progesteron')),
        ),
        TextButton.icon(
          onPressed: () => _addTest(HeatTestType.cytology),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Cytologia')),
        ),
      ]),
      if (tests.isEmpty)
        Text(tr('Brak badań. Wyniki wpisuj z datą pobrania – tak jak podało laboratorium.'),
            style: const TextStyle(color: K9.faint, fontSize: 12)),
      for (final t in tests)
        ListRow(
          icon: t.type == HeatTestType.progesterone ? Icons.science_rounded : Icons.biotech_rounded,
          color: K9.blue,
          title: t.type == HeatTestType.progesterone
              ? tr('Progesteron {0} {1}', [t.value == null ? '—' : fmtNum(t.value!, 1), t.unit])
              : tr('Cytologia: {0}', [t.cytology?.label ?? '—']),
          subtitle: [
            fmtDate(t.date),
            if (t.progesteroneHint != null) t.progesteroneHint!,
            if (t.notes.isNotEmpty) t.notes,
          ].join(' · '),
          trailing: IconButton(
            tooltip: tr('Usuń'),
            icon: const Icon(Icons.close_rounded, color: K9.faint, size: 20),
            onPressed: () => setState(() => tests.remove(t)),
          ),
        ),
      if (tests.any((t) => t.type == HeatTestType.progesterone))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              [
                if (progesteroneSeriesNote(tests) != null) progesteroneSeriesNote(tests)!,
                tr('Opis poziomu progesteronu jest orientacyjny (wg literatury). Laboratoria mają różne normy – wynik i dzień krycia interpretuje lekarz weterynarii.'),
              ].join(' '),
              style: const TextStyle(color: K9.faint, fontSize: 11.5)),
        ),
      gap12,
      TextField(
        controller: notes,
        maxLines: 3,
        decoration: InputDecoration(labelText: tr('Notatki (objawy, zachowanie, krycie)')),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (end != null && end!.isBefore(start)) {
            toast(context, tr('Koniec nie może być przed początkiem'));
            return;
          }
          if (ovulation != null && (ovulation!.isBefore(start) || ovulation!.difference(start).inCalDays > 40)) {
            toast(context, tr('Data owulacji musi przypadać w trakcie tej cieczki'));
            return;
          }
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => HeatStore.instance.upsert(HeatCycle(
            id: e?.id ?? newId(),
            start: dayOnly(start),
            end: end == null ? null : dayOnly(end!),
            notes: notes.text.trim(),
            symptoms: [for (final sy in heatSymptoms) if (symptoms.contains(sy)) sy],
            standingFrom: standing == null ? null : dayOnly(standing!),
            ovulation: ovulation == null ? null : dayOnly(ovulation!),
            tests: tests..sort((a, b) => a.date.compareTo(b.date)),
          )))) {
            return;
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }

  Future<void> _addTest(HeatTestType type) async {
    final t = await showDialog<HeatTest>(context: context, builder: (_) => _TestDialog(type: type, start: start));
    if (t != null) setState(() => tests.add(t));
  }
}

class _TestDialog extends StatefulWidget {
  final HeatTestType type;
  final DateTime start;
  const _TestDialog({required this.type, required this.start});
  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> {
  DateTime date = dayOnly(DateTime.now());
  String unit = 'ng/ml';
  CytologyResult? cyto;
  final value = TextEditingController();
  final notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final prog = widget.type == HeatTestType.progesterone;
    return AlertDialog(
      title: Text(widget.type.label),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DateField(label: tr('Data pobrania'), value: date, onChanged: (v) => setState(() => date = v!)),
          gap12,
          if (prog) ...[
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Wynik')),
            ),
            gap12,
            Segmented(items: const ['ng/ml', 'nmol/l'], index: unit == 'ng/ml' ? 0 : 1, onChanged: (i) => setState(() => unit = i == 0 ? 'ng/ml' : 'nmol/l')),
          ] else
            DropdownButtonFormField<CytologyResult>(
              initialValue: cyto,
              dropdownColor: K9.cardHi,
              decoration: InputDecoration(labelText: tr('Opis lekarza')),
              items: [for (final c in CytologyResult.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => setState(() => cyto = v),
            ),
          gap12,
          TextField(controller: notes, decoration: InputDecoration(labelText: tr('Notatki (laboratorium, lekarz)'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Anuluj'))),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(value.text.trim().replaceAll(',', '.'));
            if (prog && (v == null || v < 0 || v > 200)) {
              toast(context, tr('Wpisz poprawny wynik'));
              return;
            }
            if (!prog && cyto == null) {
              toast(context, tr('Wybierz opis wyniku'));
              return;
            }
            Navigator.pop(
                context,
                HeatTest(
                    id: newId(),
                    date: dayOnly(date),
                    type: widget.type,
                    value: prog ? v : null,
                    unit: unit,
                    cytology: prog ? null : cyto,
                    notes: notes.text.trim()));
          },
          child: Text(tr('Dodaj')),
        ),
      ],
    );
  }
}

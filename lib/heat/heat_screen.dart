import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'heat_logic.dart';
import 'heat_store.dart';
import '../l10n/l10n.dart';

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
                        : '${_countdown(st.daysToNext(now)!)} · '
                            '${st.intervalFromHistory ? 'średnia z Twoich wpisów' : 'typowo co ok. 6 miesięcy (dokładniej po 2 cieczkach)'}',
                    style: const TextStyle(color: K9.muted, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: h.remind,
                    onChanged: h.setRemind,
                    title: Text(tr('Powiadomienia')),
                    subtitle: Text(tr('Tydzień przed, w dniu terminu i na początek dni płodnych'),
                        style: TextStyle(color: K9.muted, fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
            gap12,
            FadeSlideIn(index: 3, child: _History(cycles: h.cycles)),
            gap12,
            Text(
              tr('Etapy i dni płodne są orientacyjne. Dokładny moment krycia najlepiej ustalić badaniem progesteronu u weterynarza.'),
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ]);
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final HeatStatus st;
  const _StageCard({required this.st});

  @override
  Widget build(BuildContext context) {
    final c = st.stage.color;
    final active = st.current != null;
    final day = st.day;
    final progress = active && day != null
        ? (day / HeatLogic.typicalLength).clamp(0.0, 1.0)
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
            if (active && st.fertileFrom != null) ...[
              const SizedBox(height: 6),
              Text(tr('Dni płodne ok.: {0} – {1}', [fmtDate(st.fertileFrom!), fmtDate(st.fertileTo!)]),
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
                'odstęp ${dayOnly(c.start).difference(dayOnly(cycles[i + 1].start)).inDays} dni',
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
            ? tr('{0}. dzień cieczki · {1}', [st.day, st.stage == HeatStage.estrus ? tr('dni płodne') : tr('początek')])
            : st.nextStart == null
                ? tr('Zapisz początek cieczki, a przewidzę kolejną.')
                : tr('Kolejna cieczka {0} ({1})', [_countdown(st.daysToNext(now)!), fmtDate(st.nextStart!)]);
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
                  await HeatStore.instance.delete(e);
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      DateField(label: tr('Początek (pierwszy dzień krwawienia)'), value: start, onChanged: (v) => setState(() => start = v!)),
      gap12,
      DateField(label: tr('Koniec (opcjonalnie)'), value: end, clearable: true, onChanged: (v) => setState(() => end = v)),
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
          await HeatStore.instance.upsert(HeatCycle(
            id: e?.id ?? newId(),
            start: dayOnly(start),
            end: end == null ? null : dayOnly(end!),
            notes: notes.text.trim(),
          ));
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

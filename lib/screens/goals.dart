import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../models_ext.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../l10n/l10n.dart';

final _s = AppStore.instance;

Color goalColor(double p, bool done) => done || p >= 1 ? K9.green : (p >= 0.5 ? K9.orange : K9.yellow);

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.track_changes_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text(tr('Cele')),
        ]),
        actions: [
          IconButton(
              onPressed: () => openGoalForm(context),
              icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange, size: 28)),
        ],
      ),
      body: ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          if (_s.goals.isEmpty) {
            return EmptyState(
              icon: Icons.flag_rounded,
              title: tr('Brak celów'),
              text: tr('Ustaw cel: egzamin BH-VT lub IGP, championat, kilometry albo wagę docelową.'),
              action: tr('Dodaj cel'),
              onAction: () => openGoalForm(context),
            );
          }
          final done = _s.goals.where((g) => g.done || _s.goalProgress(g).$1 >= 1).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            K9Card(
              child: Row(children: [
                RingGauge(
                  value: done / _s.goals.length,
                  size: 70,
                  stroke: 8,
                  gradient: const LinearGradient(colors: [K9.orange, K9.yellow, K9.green, K9.orange]),
                  center: Text('$done/${_s.goals.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(tr('Osiągnięte cele. Postęp liczy się sam z treningów, wystaw i pomiarów wagi.'),
                      style: TextStyle(color: Color(0xFFCFCFD4), fontSize: 13.5)),
                ),
              ]),
            ),
            gap12,
            for (final (i, g) in _s.goals.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(index: i, child: _GoalCard(g: g)),
              ),
          ]);
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal g;
  const _GoalCard({required this.g});

  @override
  Widget build(BuildContext context) {
    final (p, label) = _s.goalProgress(g);
    final achieved = g.done || p >= 1;
    final c = goalColor(p, g.done);
    return K9Card(
      onTap: () => openGoalForm(context, existing: g),
      child: Row(children: [
        RingGauge(
          value: p,
          size: 58,
          stroke: 6,
          color: c,
          center: achieved
              ? const Icon(Icons.check_rounded, color: K9.green, size: 28)
              : Text('${(p * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: K9.muted, fontSize: 13)),
            if (g.deadline != null && !achieved)
              Text(tr('Termin: {0} ({1})', [fmtDate(g.deadline!), relDays(g.deadline!)]),
                  style: const TextStyle(color: K9.faint, fontSize: 12)),
          ]),
        ),
        Icon(g.type.icon, color: K9.faint, size: 20),
      ]),
    );
  }
}

Future<void> openGoalForm(BuildContext context, {Goal? existing}) =>
    showFormSheet(context, _GoalForm(existing: existing));

class _GoalForm extends StatefulWidget {
  final Goal? existing;
  const _GoalForm({this.existing});
  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final g = widget.existing == null
      ? Goal(id: newId(), type: GoalType.exam, title: tr('BH-VT'), start: dayOnly(DateTime.now()))
      : Goal.fromJson(widget.existing!.toJson());
  late final title = TextEditingController(text: g.title);
  late final target = TextEditingController(text: g.target == null ? '' : fmtNum(g.target!, g.type == GoalType.weight ? 1 : 0));

  void _setType(GoalType t) {
    g.type = t;
    final now = DateTime.now();
    switch (t) {
      case GoalType.exam:
        title.text = 'BH-VT';
      case GoalType.title:
        g.championship = Championship.pl;
        title.text = Championship.pl.label;
      case GoalType.km:
        g.start = DateTime(now.year);
        g.deadline = DateTime(now.year, 12, 31);
        target.text = '1000';
        title.text = '1000 km w ${now.year}';
      case GoalType.weight:
        final tw = _s.dog?.targetWeightKg;
        target.text = tw == null ? '' : fmtNum(tw);
        g.startValue = _s.dog?.weightKg;
        title.text = 'Waga docelowa';
      case GoalType.custom:
        title.text = '';
    }
  }

  Widget _chip(String label, bool sel, VoidCallback on) => ChoiceChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: K9.orange,
        backgroundColor: K9.cardHi,
        side: BorderSide.none,
        labelStyle: TextStyle(color: sel ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => setState(on),
      );

  @override
  Widget build(BuildContext context) {
    final manual = g.type == GoalType.exam || g.type == GoalType.custom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? tr('Nowy cel') : tr('Edytuj cel'),
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'cel')) {
                    await _s.deleteGoal(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in GoalType.values) _chip(t.label, t == g.type, () => _setType(t)),
      ]),
      gap16,
      if (g.type == GoalType.exam) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in examPresets) _chip(e, title.text == e, () => title.text = e),
        ]),
        gap12,
      ],
      if (g.type == GoalType.title) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in Championship.values)
            _chip(c.label, g.championship == c, () {
              g.championship = c;
              title.text = c.label;
            }),
        ]),
        gap12,
      ],
      TextField(controller: title, decoration: InputDecoration(labelText: tr('Nazwa celu *'))),
      if (g.type == GoalType.km || g.type == GoalType.weight) ...[
        gap12,
        TextField(
          controller: target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: g.type == GoalType.km ? tr('Cel (km)') : tr('Waga docelowa (kg)')),
        ),
      ],
      gap12,
      Row(children: [
        Expanded(child: DateField(label: tr('Od'), value: g.start, onChanged: (v) => setState(() => g.start = v!))),
        const SizedBox(width: 12),
        Expanded(
            child: DateField(
                label: tr('Termin'), value: g.deadline, clearable: true, onChanged: (v) => setState(() => g.deadline = v))),
      ]),
      if (manual) ...[
        gap16,
        Row(children: [
          Text(tr('Przygotowanie'), style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${(g.manualProgress * 100).round()}%', style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
        ]),
        Slider(
          value: g.manualProgress,
          divisions: 20,
          activeColor: K9.orange,
          inactiveColor: K9.cardHi,
          onChanged: g.done ? null : (v) => setState(() => g.manualProgress = v),
        ),
      ],
      if (g.type != GoalType.km && g.type != GoalType.weight)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(g.type == GoalType.title ? tr('Tytuł zdobyty') : tr('Zaliczone')),
          value: g.done,
          onChanged: (v) => setState(() {
            g.done = v;
            g.doneDate = v ? dayOnly(DateTime.now()) : null;
          }),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (title.text.trim().isEmpty) {
            toast(context, tr('Wpisz nazwę celu'));
            return;
          }
          g
            ..title = title.text.trim()
            ..target = parseNum(target.text);
          if (g.type != GoalType.title) g.championship = null;
          if (g.type == GoalType.weight && g.startValue == null) g.startValue = _s.dog?.weightKg;
          await _s.upsertGoal(g);
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

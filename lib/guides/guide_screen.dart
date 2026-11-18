import 'package:material_ui/material_ui.dart';

import '../modules/modules.dart';
import '../screens/forms.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'guide_store.dart';
import 'guides_data.dart';
import '../l10n/l10n.dart';

void openGuide(BuildContext context, AppModule m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuideScreen(module: m)));

const _statusColors = [K9.faint, K9.yellow, K9.green];

/// Przewodnik treningowy: ćwiczenia krok po kroku i postęp psa.
class GuideScreen extends StatelessWidget {
  final AppModule module;
  const GuideScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final g = guides[module]!;
    final st = GuideStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(module.icon, color: K9.orange),
          const SizedBox(width: 10),
          Flexible(child: Text(module.label, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openTrainingForm(context, discipline: g.discipline),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Zapisz trening'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final done = g.exercises.where((e) => st.statusOf(e.id) == 2).length;
          final doing = g.exercises.where((e) => st.statusOf(e.id) == 1).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            K9Card(
              child: Row(children: [
                RingGauge(
                  value: done / g.exercises.length,
                  size: 76,
                  stroke: 8,
                  color: K9.green,
                  center: Text('$done/${g.exercises.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${g.statusLabels[2]}: $done · ${g.statusLabels[1]}: $doing',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(g.intro, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
                  ]),
                ),
              ]),
            ),
            if (g.warning != null) ...[
              gap12,
              K9Card(
                color: const Color(0xFF2A1512),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: K9.red),
                  const SizedBox(width: 10),
                  Expanded(child: Text(g.warning!, style: const TextStyle(fontSize: 13.5))),
                ]),
              ),
            ],
            gap12,
            for (final (i, e) in g.exercises.indexed) ...[
              FadeSlideIn(index: i, child: _ExerciseCard(e: e, labels: g.statusLabels)),
              const SizedBox(height: 10),
            ],
          ]);
        },
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final GuideExercise e;
  final List<String> labels;
  const _ExerciseCard({required this.e, required this.labels});

  @override
  Widget build(BuildContext context) {
    final st = GuideStore.instance;
    final s = st.statusOf(e.id);
    return K9Card(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(
            s == 2 ? Icons.check_circle_rounded : (s == 1 ? Icons.timelapse_rounded : Icons.circle_outlined),
            color: _statusColors[s],
          ),
          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(e.goal, style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, step) in e.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: K9.orange.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(color: K9.orange, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: const TextStyle(fontSize: 14, height: 1.35))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 18, color: K9.yellow),
                const SizedBox(width: 8),
                Expanded(child: Text(e.tip, style: const TextStyle(color: K9.muted, fontSize: 13, height: 1.3))),
              ]),
            ),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  for (var k = 0; k < 3; k++)
                    ButtonSegment(value: k, label: Text(labels[k], style: const TextStyle(fontSize: 12.5))),
                ],
                selected: {s},
                showSelectedIcon: false,
                onSelectionChanged: (v) => st.setStatus(e.id, v.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

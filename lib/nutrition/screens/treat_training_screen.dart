import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../energy.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import 'products_screen.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

void openTreatTraining(BuildContext context, {Discipline? discipline}) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => TreatTrainingScreen(discipline: discipline)));

/// Trening z liczeniem nagród. Po zakończeniu zapisuje trening i przysmaki,
/// a porcja karmy na resztę dnia przelicza się automatycznie.
class TreatTrainingScreen extends StatefulWidget {
  final Discipline? discipline;
  const TreatTrainingScreen({super.key, this.discipline});
  @override
  State<TreatTrainingScreen> createState() => _TreatTrainingScreenState();
}

class _TreatTrainingScreenState extends State<TreatTrainingScreen> {
  late Discipline disc = widget.discipline ?? Discipline.obedience;
  DateTime? started;
  Timer? timer;
  final counts = <String, double>{};
  final selected = <String>[];

  /// Stałe ID treningu: ponowienie zapisu nie tworzy drugiego treningu ani drugiej porcji.
  late final String _id = newId();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final treats = _n.ofType({ProductType.treat});
    selected.addAll(treats.take(3).map((p) => p.id));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => started = DateTime.now());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  double get kcal => counts.entries.fold(0.0, (a, e) {
        final p = _n.product(e.key);
        if (p == null) return a;
        return a + (p.kcalPerPiece ?? p.kcalPerGram) * e.value;
      });

  Future<void> _addTreat() async {
    final all = _n.ofType({ProductType.treat});
    final rest = all.where((p) => !selected.contains(p.id)).toList();
    final pick = await showModalBottomSheet<FoodProduct>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(tr('Wybierz nagrodę')),
          for (final p in rest)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ProductTile(p: p, onTap: () => Navigator.pop(c, p))),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await addProductFlow(context, type: ProductType.treat);
              if (c.mounted) Navigator.pop(c, p);
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Nowy przysmak (skan lub ręcznie)')),
          ),
        ]),
      ),
    );
    if (pick != null) setState(() => selected.add(pick.id));
  }

  Future<void> _finish() async {
    final mins = started == null ? 0 : DateTime.now().difference(started!).inMinutes;
    var rpe = 5.0;
    final duration = TextEditingController(text: '${mins < 1 ? 1 : mins}');
    final ok = await showFormSheet<bool>(
      context,
      StatefulBuilder(
        builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(tr('Zakończ trening')),
          TextField(
              controller: duration,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Czas (min)'))),
          gap12,
          Row(children: [
            Text(tr('Intensywność'), style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${rpe.round()}/10', style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
          ]),
          Slider(
              value: rpe,
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: K9.orange,
              inactiveColor: K9.cardHi,
              onChanged: (v) => set(() => rpe = v)),
          Text(tr('Nagrody: {0} kcal', [kcal.round()]), style: const TextStyle(color: K9.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Zapisz trening'))),
        ]),
      ),
    );
    if (ok != true || !mounted || _saving) return;
    final typed = int.tryParse(duration.text.trim());
    if (typed == null || typed < 1 || typed > 24 * 60) {
      toast(context, tr('Podaj czas w pełnych minutach (1–{0})', [24 * 60]));
      return;
    }
    final t = TrainingSession(
      id: _id,
      discipline: disc,
      date: started ?? DateTime.now(),
      durationMin: typed,
      rpe: rpe.round(),
      notes: _summary(),
    );
    DailyPlan? plan;
    setState(() => _saving = true);
    final saved = await saveGuarded(context, () async => plan = await _n.saveTrainingWithTreats(t, Map.of(counts)));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) return; // licznik i czas zostają – można ponowić
    timer?.cancel();
    final pl = plan;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Trening zapisany')),
        content: Text(pl == null
            ? tr('Nagrody zapisane w dzienniku.')
            : tr('Nagrody: {0} kcal.\nPozostało na dziś: {1} kcal.\nProponowana porcja karmy na resztę dnia: {2} g.', [kcal.round(), pl.remainingKcal.round(), pl.remainingGrams.round()])),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('OK')))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  String _summary() {
    final parts = <String>[];
    counts.forEach((id, v) {
      if (v > 0) parts.add(tr('{0}: {1} szt.', [_n.product(id)?.title ?? tr('przysmak'), fmtNum(v, 0)]));
    });
    return parts.isEmpty ? '' : tr('Nagrody – {0}', [parts.join(', ')]);
  }

  String _clock() {
    if (started == null) return '00:00';
    final s = DateTime.now().difference(started!).inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = _n.plan;
    final remaining = plan == null ? null : plan.remainingKcal - kcal;
    return PopScope(
      canPop: started == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDelete(context, tr('trwający trening (bez zapisu)'));
        if (leave && context.mounted) {
          timer?.cancel();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Trening z nagrodami'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          if (started == null) ...[
            Text(tr('Dyscyplina'), style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in Discipline.values)
                ChoiceChip(
                  label: Text(d.label),
                  avatar: Icon(d.icon, size: 18, color: d == disc ? Colors.black : d.color),
                  selected: d == disc,
                  showCheckmark: false,
                  selectedColor: K9.orange,
                  backgroundColor: K9.cardHi,
                  side: BorderSide.none,
                  labelStyle: TextStyle(color: d == disc ? Colors.black : K9.text, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (_) => setState(() => disc = d),
                ),
            ]),
            gap16,
          ],
          K9Card(
            child: Row(children: [
              IconBadge(disc.icon, disc.color, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(disc.label, style: const TextStyle(color: K9.muted)),
                  Text(_clock(), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr('{0} kcal', [kcal.round()]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: K9.orange)),
                Text(tr('w nagrodach'), style: TextStyle(color: K9.muted, fontSize: 12)),
                if (remaining != null)
                  Text(tr('zostanie {0} kcal', [remaining.round()]), style: const TextStyle(color: K9.faint, fontSize: 12)),
              ]),
            ]),
          ),
          gap12,
          SectionTitle(tr('Nagrody'), icon: Icons.cookie_rounded),
          if (selected.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(tr('Dodaj przysmaki, których używasz. Najlepiej z masą jednej sztuki.'),
                  style: TextStyle(color: K9.muted)),
            ),
          for (final id in selected)
            if (_n.product(id) != null) _TreatCounter(
              p: _n.product(id)!,
              count: counts[id] ?? 0,
              onChanged: (v) => setState(() => counts[id] = v < 0 ? 0 : v),
            ),
          TextButton.icon(onPressed: _addTreat, icon: const Icon(Icons.add_rounded), label: Text(tr('Dodaj nagrodę'))),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: started == null
                ? FilledButton.icon(
                    onPressed: _start, icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('Rozpocznij trening')))
                : FilledButton.icon(
                    onPressed: _saving ? null : _finish, icon: const Icon(Icons.stop_rounded), label: Text(tr('Zakończ i zapisz'))),
          ),
        ),
      ),
    );
  }
}

class _TreatCounter extends StatelessWidget {
  final FoodProduct p;
  final double count;
  final ValueChanged<double> onChanged;
  const _TreatCounter({required this.p, required this.count, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final perPiece = p.kcalPerPiece;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: K9Card(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ProductThumb(p: p, size: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(perPiece == null ? tr('liczone w gramach') : tr('{0} kcal / szt.', [fmtNum(perPiece)]),
                  style: const TextStyle(color: K9.muted, fontSize: 12.5)),
            ]),
          ),
          IconButton(tooltip: tr('Odejmij'), 
              onPressed: count > 0 ? () => onChanged(count - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 30)),
          SizedBox(
            width: 40,
            child: Text(fmtNum(count, 0),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          GestureDetector(
            onLongPress: () => onChanged(count + 5),
            child: IconButton(tooltip: tr('Dodaj'), 
              onPressed: () => onChanged(count + 1),
              icon: const Icon(Icons.add_circle_rounded, size: 40, color: K9.orange),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../models.dart';
import '../models_ext.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/photo.dart';
import '../l10n/l10n.dart';

final _s = AppStore.instance;

Color wearColor(double w) => w >= 1 ? K9.red : (w >= 0.8 ? K9.yellow : K9.green);

class GearScreen extends StatelessWidget {
  const GearScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
        Icon(Icons.backpack_outlined, color: K9.orange),
        SizedBox(width: 10),
        Text(tr('Sprzęt')),
      ])),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openGearForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          final active = _s.gear.where((g) => !g.retired).toList()
            ..sort((a, b) => _s.gearWear(b).compareTo(_s.gearWear(a)));
          final retired = _s.gear.where((g) => g.retired).toList();
          if (_s.gear.isEmpty) {
            return EmptyState(
              icon: Icons.backpack_rounded,
              title: tr('Brak sprzętu'),
              text: tr('Dodaj szelki, linkę czy rower. Policzę kilometry z treningów i przypomnę o wymianie.'),
              action: tr('Dodaj sprzęt'),
              onAction: () => openGearForm(context),
            );
          }
          final value = _s.gear.where((g) => !g.retired).fold(0.0, (a, g) => a + (g.price ?? 0));
          final toReplace = active.where((g) => _s.gearWear(g) >= 0.8).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            K9Card(
              child: Row(children: [
                Expanded(child: StatValue(label: tr('W użyciu'), value: '${active.length}')),
                Expanded(child: StatValue(label: tr('Do wymiany'), value: '$toReplace', color: K9.yellow)),
                Expanded(child: StatValue(label: tr('Wartość'), value: fmtNum(value, 0), unit: tr('zł'))),
              ]),
            ),
            gap12,
            for (final (i, g) in active.indexed) FadeSlideIn(index: i, child: _GearCard(g: g)),
            if (retired.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(tr('Wycofany'), style: TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
              ),
              for (final g in retired) Opacity(opacity: 0.55, child: _GearCard(g: g)),
            ],
          ]);
        },
      ),
    );
  }
}

class _GearCard extends StatelessWidget {
  final GearItem g;
  const _GearCard({required this.g});

  @override
  Widget build(BuildContext context) {
    final km = _s.gearKm(g);
    final wear = _s.gearWear(g);
    final c = wearColor(wear);
    final r = g.replaceDate;
    final details = <String>[
      if (g.purchased != null) tr('kupione {0}', [fmtDate(g.purchased!)]),
      if (g.disciplines.isNotEmpty) tr('{0}{1} km', [fmtKm(km), g.maxKm != null ? ' / ${fmtKm(g.maxKm!)}' : '']),
      if (r != null) tr('wymiana {0}', [relDays(r)]),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: K9Card(
        padding: const EdgeInsets.all(12),
        onTap: () => openGearForm(context, existing: g),
        child: Column(children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 52,
                height: 52,
                child: g.photo == null
                    ? Container(
                        color: K9.orange.withValues(alpha: 0.14), child: Icon(g.category.icon, color: K9.orange, size: 26))
                    : FileStore.image(g.photo!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text([g.category.label, if (g.brand.isNotEmpty) g.brand].join(' · '),
                    style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                if (details.isNotEmpty)
                  Text(details.join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: K9.faint, fontSize: 12)),
              ]),
            ),
            if (g.maxKm != null || r != null)
              RingGauge(
                value: wear.clamp(0, 1).toDouble(),
                size: 46,
                stroke: 5,
                color: c,
                center: Text('${(wear * 100).round()}%', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
          ]),
          if (!g.retired && wear >= 1) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: K9.red, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(tr('Czas na wymianę'), style: TextStyle(color: K9.red, fontWeight: FontWeight.w600, fontSize: 13))),
              TextButton(
                onPressed: () {
                  g.retired = true;
                  _s.upsertGear(g);
                },
                child: Text(tr('Wycofaj')),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

Future<void> openGearForm(BuildContext context, {GearItem? existing}) =>
    showFormSheet(context, _GearForm(existing: existing));

const _defaults = {
  GearCategory.harness: (18, 1500.0, {Discipline.canicross, Discipline.bikejoring}),
  GearCategory.leash: (24, null, <Discipline>{}),
  GearCategory.bungee: (12, 800.0, {Discipline.canicross, Discipline.bikejoring}),
  GearCategory.bike: (null, null, {Discipline.bikejoring}),
  GearCategory.collar: (24, null, <Discipline>{}),
  GearCategory.booties: (3, 150.0, {Discipline.canicross, Discipline.bikejoring}),
  GearCategory.other: (null, null, <Discipline>{}),
};

class _GearForm extends StatefulWidget {
  final GearItem? existing;
  const _GearForm({this.existing});
  @override
  State<_GearForm> createState() => _GearFormState();
}

class _GearFormState extends State<_GearForm> {
  late final g = widget.existing == null
      ? (GearItem(id: newId(), category: GearCategory.harness, name: '', purchased: dayOnly(DateTime.now()))
        ..replaceAfterMonths = 18
        ..maxKm = 1500
        ..disciplines = {Discipline.canicross, Discipline.bikejoring})
      : GearItem.fromJson(widget.existing!.toJson());
  late final name = TextEditingController(text: g.name);
  late final brand = TextEditingController(text: g.brand);
  late final price = TextEditingController(text: g.price == null ? '' : fmtNum(g.price!, 0));
  late final months = TextEditingController(text: g.replaceAfterMonths?.toString() ?? '');
  late final maxKm = TextEditingController(text: g.maxKm == null ? '' : fmtNum(g.maxKm!, 0));
  late final notes = TextEditingController(text: g.notes);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? tr('Nowy sprzęt') : tr('Edytuj sprzęt'),
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, tr('sprzęt'))) {
                    if (!context.mounted) return;
                    if (!await saveGuarded(context, () => _s.deleteGear(widget.existing!), done: tr('Usunięto'))) return;
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      Row(children: [
        GestureDetector(
          onTap: () async {
            final r = await pickPhoto(context);
            if (r != null) setState(() => g.photo = r);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 72,
              height: 72,
              child: g.photo == null
                  ? Container(color: K9.cardHi, child: const Icon(Icons.add_a_photo_outlined, color: K9.orange))
                  : FileStore.image(g.photo!),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Nazwa *'))),
            const SizedBox(height: 8),
            TextField(controller: brand, decoration: InputDecoration(labelText: tr('Marka / model'))),
          ]),
        ),
      ]),
      gap12,
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in GearCategory.values)
          ChoiceChip(
            label: Text(c.label),
            avatar: Icon(c.icon, size: 18, color: c == g.category ? Colors.black : K9.orange),
            selected: c == g.category,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(color: c == g.category ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() {
              g.category = c;
              if (widget.existing == null) {
                final d = _defaults[c]!;
                months.text = d.$1?.toString() ?? '';
                maxKm.text = d.$2 == null ? '' : fmtNum(d.$2!, 0);
                g.disciplines = {...d.$3};
              }
            }),
          ),
      ]),
      gap12,
      Row(children: [
        Expanded(
            flex: 3,
            child: DateField(label: tr('Data zakupu'), value: g.purchased, clearable: true, onChanged: (v) => setState(() => g.purchased = v))),
        const SizedBox(width: 12),
        Expanded(
            flex: 2,
            child: TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Cena (zł)')))),
      ]),
      gap12,
      Row(children: [
        Expanded(
            child: TextField(
                controller: months,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Wymiana po (mies.)')))),
        const SizedBox(width: 12),
        Expanded(
            child: TextField(
                controller: maxKm,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('lub po (km)')))),
      ]),
      gap16,
      Text(tr('Licz kilometry z treningów'), style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in Discipline.values.where((d) => d.hasDistance && d != Discipline.recovery))
          FilterChip(
            label: Text(d.label),
            selected: g.disciplines.contains(d),
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(
                color: g.disciplines.contains(d) ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => setState(() => v ? g.disciplines.add(d) : g.disciplines.remove(d)),
          ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Przypomnij o wymianie')),
        value: g.remind,
        onChanged: (v) => setState(() => g.remind = v),
      ),
      if (widget.existing != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Wycofany z użytku')),
          value: g.retired,
          onChanged: (v) => setState(() => g.retired = v),
        ),
      TextField(controller: notes, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('Notatki (rozmiar, serwis)'))),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (name.text.trim().isEmpty) {
            toast(context, tr('Wpisz nazwę'));
            return;
          }
          g
            ..name = name.text.trim()
            ..brand = brand.text.trim()
            ..price = parseNum(price.text)
            ..replaceAfterMonths = int.tryParse(months.text.trim())
            ..maxKm = parseNum(maxKm.text)
            ..notes = notes.text.trim();
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => _s.upsertGear(g))) return;
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

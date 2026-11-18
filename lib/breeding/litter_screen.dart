import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'breeding_logic.dart';
import 'breeding_models.dart';
import 'breeding_store.dart';

void openLitter(BuildContext context, Mating m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LitterScreen(mating: m)));

String _g(int g) => g >= 1000 ? '${fmtNum(g / 1000, 2)} kg' : '$g g';

/// Miot: szczenięta i ich ważenia.
class LitterScreen extends StatelessWidget {
  final Mating mating;
  const LitterScreen({super.key, required this.mating});

  @override
  Widget build(BuildContext context) {
    final b = BreedingStore.instance;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final l = mating.litter;
        if (l == null) return const Scaffold();
        final now = DateTime.now();
        final age = l.ageDays(now);
        return Scaffold(
          appBar: AppBar(
            title: Text('Miot ${fmtDateShort(l.born)}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => openLitterForm(context, mating),
              ),
            ],
          ),
          floatingActionButton: l.puppies.isEmpty
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: K9.orange,
                  foregroundColor: Colors.black,
                  onPressed: () => showFormSheet(context, _WeighAllForm(mating: mating)),
                  icon: const Icon(Icons.scale_rounded),
                  label: const Text('Ważenie miotu', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            K9Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: StatValue(label: 'Wiek', value: age < 14 ? '$age' : '${age ~/ 7}', unit: age < 14 ? 'dni' : 'tyg.')),
                  Expanded(child: StatValue(label: 'Psy', value: '${l.males}')),
                  Expanded(child: StatValue(label: 'Suki', value: '${l.females}')),
                ]),
                if (mating.partner.isNotEmpty || l.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    [if (mating.partner.isNotEmpty) 'Ojciec: ${mating.partner}', if (l.notes.isNotEmpty) l.notes].join(' · '),
                    style: const TextStyle(color: K9.muted, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 10),
                Text(_careTip(age), style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
              ]),
            ),
            gap12,
            K9Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('Szczenięta', icon: Icons.pets_rounded, action: 'Dodaj', onAction: () => openPuppyForm(context, mating)),
                if (l.puppies.isEmpty) const Text('Dodaj szczenięta, żeby zapisywać ich masę.', style: TextStyle(color: K9.muted)),
                for (final p in l.puppies) _PuppyRow(mating: mating, p: p, born: l.born),
              ]),
            ),
            gap12,
            const Text(
              'Szczenię powinno codziennie przybierać i podwoić masę urodzeniową w ok. 7–10 dni. '
              'Spadek wagi w pierwszych dniach – skontaktuj się z weterynarzem.',
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }

  static String _careTip(int age) => switch (age) {
        < 3 => 'Pierwsze dni: waż szczenięta 2× dziennie, pilnuj ciepła w kojcu (ok. 30 °C) i czy każde ssie.',
        < 14 => 'Waż codziennie o tej samej porze. Oczy otworzą się ok. 10.–14. dnia.',
        < 21 => 'Ok. 2.–3. tygodnia pierwsze odrobaczanie. Szczenięta zaczynają chodzić.',
        < 35 => 'Od 3.–4. tygodnia pierwsze papki i socjalizacja: nowe dźwięki, podłoża, ludzie.',
        < 56 => 'Odrobaczanie co 2 tygodnie, pierwsze szczepienie ok. 6.–8. tygodnia. Przegląd miotu w związku.',
        _ => 'Szczenięta mogą iść do nowych domów od ok. 8. tygodnia (po przeglądzie miotu i czipowaniu).',
      };
}

class _PuppyRow extends StatelessWidget {
  final Mating mating;
  final Puppy p;
  final DateTime born;
  const _PuppyRow({required this.mating, required this.p, required this.born});

  @override
  Widget build(BuildContext context) {
    final ch = p.lastChange;
    final late = !PuppyGrowth.doubledOnTime(p, born);
    final color = p.losing || late ? K9.red : (p.female ? const Color(0xFFFF6FAE) : K9.blue);
    return ListRow(
      icon: p.female ? Icons.female_rounded : Icons.male_rounded,
      color: color,
      title: p.name,
      subtitle: [
        if (p.color.isNotEmpty) p.color,
        if (p.birthGrams != null) 'ur. ${_g(p.birthGrams!)}',
        if (p.losing) 'spadek wagi!' else if (late) 'wolny przyrost',
      ].join(' · '),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(p.lastGrams == null ? '—' : _g(p.lastGrams!), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (ch != null)
          Text('${ch >= 0 ? '+' : ''}$ch g',
              style: TextStyle(color: ch < 0 ? K9.red : K9.green, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      onTap: () => openPuppyForm(context, mating, existing: p),
    );
  }
}

// --- Poród / miot --------------------------------------------------------------

void openLitterForm(BuildContext context, Mating m) => showFormSheet(context, _LitterForm(mating: m));

class _LitterForm extends StatefulWidget {
  final Mating mating;
  const _LitterForm({required this.mating});
  @override
  State<_LitterForm> createState() => _LitterFormState();
}

class _LitterFormState extends State<_LitterForm> {
  late final Litter? l = widget.mating.litter;
  late DateTime born = l?.born ?? dayOnly(DateTime.now());
  late final males = TextEditingController(text: l == null ? '' : '${l!.males}');
  late final females = TextEditingController(text: l == null ? '' : '${l!.females}');
  late final stillborn = TextEditingController(text: (l?.stillborn ?? 0) == 0 ? '' : '${l!.stillborn}');
  late final notes = TextEditingController(text: l?.notes ?? '');

  @override
  Widget build(BuildContext context) {
    final isNew = l == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(isNew ? 'Poród – nowy miot' : 'Edytuj miot'),
      DateField(label: 'Data porodu', value: born, onChanged: (v) => setState(() => born = v!)),
      if (isNew) ...[
        gap12,
        Row(children: [
          Expanded(child: _num(males, 'Psy (szt.)')),
          const SizedBox(width: 10),
          Expanded(child: _num(females, 'Suki (szt.)')),
        ]),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 6),
          child: Text('Utworzę listę szczeniąt – imiona i masę uzupełnisz później.',
              style: TextStyle(color: K9.faint, fontSize: 12)),
        ),
      ],
      gap12,
      _num(stillborn, 'Martwo urodzone (opcjonalnie)'),
      gap12,
      TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notatki (przebieg porodu)')),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final m = widget.mating;
          final sb = int.tryParse(stillborn.text) ?? 0;
          if (isNew) {
            final nm = int.tryParse(males.text) ?? 0, nf = int.tryParse(females.text) ?? 0;
            var k = 0;
            m.litter = Litter(born: dayOnly(born), stillborn: sb, notes: notes.text.trim(), puppies: [
              for (var i = 0; i < nm; i++) Puppy(id: '${newId()}${k++}', name: 'Pies ${i + 1}', female: false),
              for (var i = 0; i < nf; i++) Puppy(id: '${newId()}${k++}', name: 'Suka ${i + 1}', female: true),
            ]);
          } else {
            m.litter!
              ..born = dayOnly(born)
              ..stillborn = sb
              ..notes = notes.text.trim();
          }
          m.status = PregnancyStatus.whelped;
          await BreedingStore.instance.upsert(m);
          if (!context.mounted) return;
          Navigator.pop(context);
          if (isNew) openLitter(context, m);
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

Widget _num(TextEditingController c, String label) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
    );

// --- Szczenię ------------------------------------------------------------------

void openPuppyForm(BuildContext context, Mating m, {Puppy? existing}) =>
    showFormSheet(context, _PuppyForm(mating: m, existing: existing));

class _PuppyForm extends StatefulWidget {
  final Mating mating;
  final Puppy? existing;
  const _PuppyForm({required this.mating, this.existing});
  @override
  State<_PuppyForm> createState() => _PuppyFormState();
}

class _PuppyFormState extends State<_PuppyForm> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final color = TextEditingController(text: widget.existing?.color ?? '');
  late final grams = TextEditingController();
  late bool female = widget.existing?.female ?? true;
  DateTime date = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final p = widget.existing;
    final l = widget.mating.litter!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        p == null ? 'Nowe szczenię' : p.name,
        onDelete: p == null
            ? null
            : () async {
                if (await confirmDelete(context, 'szczenię ${p.name}')) {
                  l.puppies.remove(p);
                  await BreedingStore.instance.touch();
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Imię')),
      gap12,
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Pies')), ButtonSegment(value: true, label: Text('Suka'))],
        selected: {female},
        onSelectionChanged: (s) => setState(() => female = s.first),
        showSelectedIcon: false,
      ),
      gap12,
      TextField(controller: color, decoration: const InputDecoration(labelText: 'Umaszczenie / znaki szczególne')),
      gap16,
      const Text('Ważenie', style: TextStyle(fontWeight: FontWeight.w700)),
      gap12,
      Row(children: [
        Expanded(child: DateField(label: 'Data', value: date, onChanged: (v) => setState(() => date = v!))),
        const SizedBox(width: 10),
        Expanded(child: _num(grams, 'Masa (g)')),
      ]),
      if (p != null && p.weights.isNotEmpty) ...[
        gap12,
        for (final w in p.weights.reversed.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text('${fmtDate(w.date)} · ${l.born.difference(w.date).inDays.abs()}. dzień',
                    style: const TextStyle(color: K9.muted, fontSize: 13)),
              ),
              Text(_g(w.grams), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (name.text.trim().isEmpty) {
            toast(context, 'Podaj imię szczenięcia');
            return;
          }
          final pup = p ?? Puppy(id: newId(), name: '');
          pup
            ..name = name.text.trim()
            ..female = female
            ..color = color.text.trim();
          final g = int.tryParse(grams.text);
          if (g != null && g > 0) pup.setWeight(date, g);
          if (p == null) l.puppies.add(pup);
          await BreedingStore.instance.touch();
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

/// Szybkie ważenie wszystkich szczeniąt naraz.
class _WeighAllForm extends StatefulWidget {
  final Mating mating;
  const _WeighAllForm({required this.mating});
  @override
  State<_WeighAllForm> createState() => _WeighAllFormState();
}

class _WeighAllFormState extends State<_WeighAllForm> {
  DateTime date = dayOnly(DateTime.now());
  late final ctrls = {for (final p in widget.mating.litter!.puppies) p.id: TextEditingController()};

  @override
  Widget build(BuildContext context) {
    final l = widget.mating.litter!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetTitle('Ważenie miotu'),
      DateField(label: 'Data', value: date, onChanged: (v) => setState(() => date = v!)),
      gap12,
      for (final p in l.puppies)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(p.female ? Icons.female_rounded : Icons.male_rounded, color: p.female ? const Color(0xFFFF6FAE) : K9.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(
              width: 130,
              child: TextField(
                controller: ctrls[p.id],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'g',
                  hintText: p.lastGrams == null ? null : 'było ${p.lastGrams}',
                ),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: () async {
          var n = 0;
          for (final p in l.puppies) {
            final g = int.tryParse(ctrls[p.id]!.text);
            if (g != null && g > 0) {
              p.setWeight(date, g);
              n++;
            }
          }
          await BreedingStore.instance.touch();
          if (!context.mounted) return;
          Navigator.pop(context);
          toast(context, 'Zapisano ważenie ($n szt.)');
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

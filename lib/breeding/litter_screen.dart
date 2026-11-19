import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'breeding_logic.dart';
import 'breeding_models.dart';
import 'breeding_store.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

void openLitter(BuildContext context, Mating m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LitterScreen(mating: m)));

String _g(int g) => g >= 1000 ? tr('{0} kg', [fmtNum(g / 1000, 2)]) : '$g g';

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
            title: Text(tr('Miot {0}', [fmtDateShort(l.born)])),
            actions: [
              IconButton(
                tooltip: tr('Edytuj'),
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
                  label: Text(tr('Ważenie miotu'), style: TextStyle(fontWeight: FontWeight.w700)),
                ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            K9Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: StatValue(label: tr('Wiek'), value: age < 14 ? '$age' : '${age ~/ 7}', unit: age < 14 ? tr('dni') : tr('tyg.'))),
                  Expanded(child: StatValue(label: tr('Psy'), value: '${l.males}')),
                  Expanded(child: StatValue(label: tr('Suki'), value: '${l.females}')),
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
                SectionTitle(tr('Szczenięta'), icon: Icons.pets_rounded, action: tr('Dodaj'), onAction: () => openPuppyForm(context, mating)),
                if (l.puppies.isEmpty) Text(tr('Dodaj szczenięta, żeby zapisywać ich masę.'), style: TextStyle(color: K9.muted)),
                for (final p in l.puppies) _PuppyRow(mating: mating, p: p, born: l.born),
              ]),
            ),
            gap12,
            Text(
              tr('Szczenię powinno przybierać codziennie i podwoić masę urodzeniową w ok. 7–10 dni. W pierwszych 1–2 dobach niewielki spadek (do ok. 10%) bywa normalny – obserwuj, czy ssie. Większy lub dłuższy spadek, brak przyrostu albo słabe ssanie – skontaktuj się z lekarzem weterynarii.'),
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }

  static String _careTip(int age) => switch (age) {
        < 3 => tr('Pierwsze dni: waż szczenięta 2× dziennie, pilnuj ciepła w kojcu (ok. 30 °C) i czy każde ssie.'),
        < 14 => tr('Waż codziennie o tej samej porze. Oczy otworzą się ok. 10.–14. dnia.'),
        < 21 => tr('Odrobaczanie zwykle od 2. tygodnia, potem co 2 tygodnie – preparat i schemat ustala lekarz weterynarii. Szczenięta zaczynają chodzić.'),
        < 35 => tr('Od 3.–4. tygodnia pierwsze papki i socjalizacja: nowe dźwięki, podłoża, ludzie.'),
        < 56 => tr('Pierwsze szczepienie zwykle w 6.–8. tygodniu, kolejne co 2–4 tygodnie do ok. 16. tygodnia (WSAVA) – schemat ustala lekarz. Przegląd miotu w związku.'),
        _ => tr('Szczenięta mogą iść do nowych domów od ok. 8. tygodnia (po przeglądzie miotu i czipowaniu).'),
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
    final alert = PuppyGrowth.alert(p, born);
    final color = alert == 2 ? K9.red : (alert == 1 ? K9.yellow : (p.female ? const Color(0xFFFF6FAE) : K9.blue));
    return ListRow(
      icon: p.female ? Icons.female_rounded : Icons.male_rounded,
      color: color,
      title: p.name,
      subtitle: [
        if (p.color.isNotEmpty) p.color,
        if (p.birthGrams != null) 'ur. ${_g(p.birthGrams!)}',
        if (alert == 2 && p.losing)
          tr('spadek wagi – skontaktuj się z lekarzem')
        else if (alert == 1 && p.losing)
          tr('niewielki spadek – obserwuj')
        else if (alert == 1)
          tr('brak przyrostu – obserwuj')
        else if (late)
          tr('wolny przyrost'),
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
      SheetTitle(isNew ? tr('Poród – nowy miot') : tr('Edytuj miot')),
      DateField(label: tr('Data porodu'), value: born, onChanged: (v) => setState(() => born = v!)),
      if (isNew) ...[
        gap12,
        Row(children: [
          Expanded(child: _num(males, tr('Psy (szt.)'))),
          const SizedBox(width: 10),
          Expanded(child: _num(females, tr('Suki (szt.)'))),
        ]),
        Padding(
          padding: EdgeInsets.only(left: 4, top: 6),
          child: Text(tr('Utworzę listę szczeniąt – imiona i masę uzupełnisz później.'),
              style: TextStyle(color: K9.faint, fontSize: 12)),
        ),
      ],
      gap12,
      _num(stillborn, tr('Martwo urodzone (opcjonalnie)')),
      gap12,
      TextField(controller: notes, maxLines: 3, decoration: InputDecoration(labelText: tr('Notatki (przebieg porodu)'))),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final m = widget.mating;
          final sb = int.tryParse(stillborn.text) ?? 0;
          if (isNew) {
            final nm = int.tryParse(males.text) ?? 0, nf = int.tryParse(females.text) ?? 0;
            var k = 0;
            m.litter = Litter(born: dayOnly(born), stillborn: sb, notes: notes.text.trim(), puppies: [
              for (var i = 0; i < nm; i++) Puppy(id: '${newId()}${k++}', name: tr('Pies {0}', [i + 1]), female: false),
              for (var i = 0; i < nf; i++) Puppy(id: '${newId()}${k++}', name: tr('Suka {0}', [i + 1]), female: true),
            ]);
          } else {
            m.litter!
              ..born = dayOnly(born)
              ..stillborn = sb
              ..notes = notes.text.trim();
          }
          m.status = PregnancyStatus.whelped;
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => BreedingStore.instance.upsert(m))) return;
          if (!context.mounted) return;
          Navigator.pop(context);
          if (isNew) openLitter(context, m);
        },
        child: Text(tr('Zapisz')),
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
        p == null ? tr('Nowe szczenię') : p.name,
        onDelete: p == null
            ? null
            : () async {
                if (await confirmDelete(context, tr('szczenię {0}', [p.name]))) {
                  l.puppies.remove(p);
                  await BreedingStore.instance.touch();
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Imię'))),
      gap12,
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: false, label: Text(tr('Pies'))), ButtonSegment(value: true, label: Text(tr('Suka')))],
        selected: {female},
        onSelectionChanged: (s) => setState(() => female = s.first),
        showSelectedIcon: false,
      ),
      gap12,
      TextField(controller: color, decoration: InputDecoration(labelText: tr('Umaszczenie / znaki szczególne'))),
      gap16,
      Text(tr('Ważenie'), style: TextStyle(fontWeight: FontWeight.w700)),
      gap12,
      Row(children: [
        Expanded(child: DateField(label: tr('Data'), value: date, onChanged: (v) => setState(() => date = v!))),
        const SizedBox(width: 10),
        Expanded(child: _num(grams, tr('Masa (g)'))),
      ]),
      if (p != null && p.weights.isNotEmpty) ...[
        gap12,
        for (final w in p.weights.reversed.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(tr('{0} · {1}. dzień', [fmtDate(w.date), l.born.difference(w.date).inCalDays.abs()]),
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
            toast(context, tr('Podaj imię szczenięcia'));
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
        child: Text(tr('Zapisz')),
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
      SheetTitle(tr('Ważenie miotu')),
      DateField(label: tr('Data'), value: date, onChanged: (v) => setState(() => date = v!)),
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
                  hintText: p.lastGrams == null ? null : tr('było {0}', [p.lastGrams]),
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
          toast(context, tr('Zapisano ważenie ({0} szt.)', [n]));
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

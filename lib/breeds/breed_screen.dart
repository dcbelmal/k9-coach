import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'breed_info.dart';
import 'breeds.dart';

void openBreed(BuildContext context, Breed b) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BreedScreen(breed: b)));

void openBreedAtlas(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BreedAtlasScreen()));

/// Rasa psa z profilu (jeśli wybrana z bazy).
Breed? get currentDogBreed {
  final d = AppStore.instance.dog;
  if (d == null) return null;
  return breedById(d.breedId) ?? breedByName(d.breed);
}

/// Atlas ras – wyszukiwarka wszystkich ras z bazy.
class BreedAtlasScreen extends StatefulWidget {
  const BreedAtlasScreen({super.key});
  @override
  State<BreedAtlasScreen> createState() => _BreedAtlasScreenState();
}

class _BreedAtlasScreenState extends State<BreedAtlasScreen> {
  final q = TextEditingController();
  int? group;

  @override
  Widget build(BuildContext context) {
    final list = searchBreeds(q.text).where((b) => group == null || b.fciGroup == group).toList();
    final mine = currentDogBreed;
    return Scaffold(
      appBar: AppBar(title: const Text('Atlas ras')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        TextField(
          controller: q,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Szukaj rasy, np. malinois'),
        ),
        gap12,
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _chip('Wszystkie', group == null, () => setState(() => group = null)),
            for (var g = 1; g <= 10; g++) _chip('Gr. ${romanNumerals[g - 1]}', group == g, () => setState(() => group = g)),
          ]),
        ),
        gap12,
        if (mine != null && q.text.isEmpty && group == null) ...[
          K9Card(
            onTap: () => openBreed(context, mine),
            child: Row(children: [
              const IconBadge(Icons.pets_rounded, K9.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Rasa ${AppStore.instance.dog!.name}', style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                  Text(mine.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K9.faint),
            ]),
          ),
          gap12,
        ],
        K9Card(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(children: [
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Brak takiej rasy w bazie.', style: TextStyle(color: K9.muted))),
            for (final b in list)
              ListTile(
                title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_subtitle(b), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                trailing: const Icon(Icons.chevron_right_rounded, color: K9.faint),
                onTap: () => openBreed(context, b),
              ),
          ]),
        ),
      ]),
    );
  }

  String _subtitle(Breed b) {
    final i = breedInfoFor(b.id);
    final g = 'Grupa ${romanNumerals[b.fciGroup - 1]}';
    return i == null ? g : '$g · ${i.size.label.toLowerCase()} · ${i.weightLabel}';
  }

  Widget _chip(String t, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: sel,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          label: Text(t),
          labelStyle: TextStyle(fontWeight: FontWeight.w600, color: sel ? Colors.black : K9.text),
          selectedColor: K9.orange,
          backgroundColor: K9.card,
          side: BorderSide(color: sel ? K9.orange : K9.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
}

/// Karta rasy.
class BreedScreen extends StatelessWidget {
  final Breed breed;
  const BreedScreen({super.key, required this.breed});

  @override
  Widget build(BuildContext context) {
    final i = breedInfoFor(breed.id);
    final dog = AppStore.instance.dog;
    final isMine = dog != null && currentDogBreed?.id == breed.id;
    return Scaffold(
      appBar: AppBar(title: const Text('O rasie')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        K9Card(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1A0C), K9.card],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(breed.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(fciGroupLabel(breed.fciGroup), style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13)),
            if (i?.fciNo != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Pill(icon: Icons.menu_book_rounded, text: 'Wzorzec FCI nr ${i!.fciNo}'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: i.fciUrl(breed.fciGroup)!));
                    if (context.mounted) toast(context, 'Skopiowano link do wzorca FCI');
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Kopiuj link'),
                ),
              ]),
            ],
          ]),
        ),
        gap12,
        if (i == null)
          const K9Card(
            child: Text('Dla tej rasy nie mamy jeszcze szczegółowych danych.', style: TextStyle(color: K9.muted)),
          )
        else ...[
          K9Card(
            child: Column(children: [
              Row(children: [
                Expanded(child: StatValue(label: 'Wzrost w kłębie', value: i.heightLabel.replaceAll(' cm', ''), unit: 'cm')),
                Expanded(child: StatValue(label: 'Masa ciała', value: i.weightLabel.replaceAll(' kg', ''), unit: 'kg')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: StatValue(label: 'Długość życia', value: '${i.lifeMin}–${i.lifeMax}', unit: 'lat')),
                Expanded(child: StatValue(label: 'Wielkość', value: i.size.label)),
              ]),
            ]),
          ),
          if (isMine && dog.weightKg != null) ...[
            gap12,
            _DogVsBreed(dog: dog, info: i),
          ],
          gap12,
          K9Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Potrzeba ruchu', icon: Icons.bolt_rounded),
              Row(children: [
                for (var k = 1; k <= 5; k++)
                  Expanded(
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: k <= i.energy ? K9.orange : K9.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(i.energyLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(i.energyHint, style: const TextStyle(color: K9.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Bieganie przy rowerze / canicross: stopniowo od ok. ${i.size.runningFromMonths}. miesiąca życia.',
                  style: const TextStyle(color: K9.muted, fontSize: 13)),
            ]),
          ),
          gap12,
          K9Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Pasujące sporty i zajęcia', icon: Icons.emoji_events_outlined),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in i.sports)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: K9.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: K9.orange.withValues(alpha: 0.35)),
                    ),
                    child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
              ]),
            ]),
          ),
          gap12,
          K9Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Zalecane badania', icon: Icons.health_and_safety_outlined),
              for (final t in i.tests)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 92,
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: K9.orange)),
                    ),
                    Expanded(
                      child: Text(testDescriptions[t] ?? '',
                          style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
                    ),
                  ]),
                ),
              const SizedBox(height: 6),
              const Text('Przed kryciem i przy zakupie szczenięcia pytaj o wyniki tych badań u rodziców.',
                  style: TextStyle(color: K9.faint, fontSize: 12)),
            ]),
          ),
          gap12,
          const Text(
            'Dane orientacyjne – zakres dla suk i psów razem. Dokładne wymagania podaje wzorzec rasy FCI i klub rasy.',
            style: TextStyle(color: K9.faint, fontSize: 12),
          ),
        ],
      ]),
    );
  }
}

class _DogVsBreed extends StatelessWidget {
  final Dog dog;
  final BreedInfo info;
  const _DogVsBreed({required this.dog, required this.info});

  @override
  Widget build(BuildContext context) {
    final w = dog.weightKg!;
    final (text, color) = w < info.weightMin
        ? ('poniżej typowej masy rasy', K9.yellow)
        : w > info.weightMax
            ? ('powyżej typowej masy rasy', K9.yellow)
            : ('w typowym zakresie rasy', K9.green);
    final young = dog.birthDate != null && DateTime.now().difference(dog.birthDate!).inDays < 365;
    return K9Card(
      child: Row(children: [
        IconBadge(Icons.monitor_weight_outlined, color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dog.name}: ${fmtNum(w)} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(young ? 'Szczenię jeszcze rośnie – porównuj po 12. miesiącu.' : 'Masa $text.',
                style: const TextStyle(color: K9.muted, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

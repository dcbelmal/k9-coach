import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'breed_info.dart';
import 'breed_profile.dart';
import 'breed_sports.dart';
import 'breeds.dart';
import '../l10n/l10n.dart';

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

  /// Filtr dyscypliny i minimalnej kategorii (A lub A+B).
  Activity? sport;
  bool onlyA = false;

  Fit? _fitOf(Breed b) => sport == null ? null : sportFit(b.id, sport!.id)?.fit;

  bool _passes(Breed b) {
    if (sport == null) return true;
    final f = _fitOf(b);
    return f == Fit.a || (!onlyA && f == Fit.b);
  }

  Future<void> _pickSport() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K9.card,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                tr('Filtruj według aktywności'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all_rounded),
              title: Text(tr('Dowolna aktywność')),
              onTap: () => Navigator.pop(ctx, false),
            ),
            for (final cat in ActivityCategory.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  cat.label,
                  style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              for (final a in activities.where((a) => a.categories.first == cat))
                ListTile(
                  dense: true,
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: sport?.id == a.id ? const Icon(Icons.check_rounded, color: K9.orange) : null,
                  onTap: () => Navigator.pop(ctx, a),
                ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => sport = picked is Activity ? picked : null);
  }

  @override
  Widget build(BuildContext context) {
    final list = searchBreeds(q.text).where((b) => (group == null || b.fciGroup == group) && _passes(b)).toList();
    if (sport != null) list.sort((a, b) => _fitOf(a)!.index - _fitOf(b)!.index);
    final mine = currentDogBreed;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Atlas ras'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          TextField(
            controller: q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: tr('Szukaj rasy, np. malinois'),
            ),
          ),
          gap12,
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip(tr('Wszystkie'), group == null, () => setState(() => group = null)),
                for (var g = 1; g <= 10; g++)
                  _chip(tr('Gr. {0}', [romanNumerals[g - 1]]), group == g, () => setState(() => group = g)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(Icons.emoji_events_outlined, size: 18, color: sport == null ? K9.text : Colors.black),
                    label: Text(sport == null ? tr('Aktywność: dowolna') : sport!.name),
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: sport == null ? K9.text : Colors.black),
                    backgroundColor: sport == null ? K9.card : K9.orange,
                    side: BorderSide(color: sport == null ? K9.border : K9.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onPressed: _pickSport,
                  ),
                ),
                if (sport != null) ...[
                  _chip(tr('A i B'), !onlyA, () => setState(() => onlyA = false)),
                  _chip(tr('Tylko A'), onlyA, () => setState(() => onlyA = true)),
                ],
              ],
            ),
          ),
          gap12,
          if (mine != null && q.text.isEmpty && group == null && sport == null) ...[
            K9Card(
              onTap: () => openBreed(context, mine),
              child: Row(
                children: [
                  const IconBadge(Icons.pets_rounded, K9.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Rasa {0}', [AppStore.instance.dog!.name]),
                          style: const TextStyle(color: K9.muted, fontSize: 12.5),
                        ),
                        Text(mine.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: K9.faint),
                ],
              ),
            ),
            gap12,
          ],
          K9Card(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                if (list.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      sport == null
                          ? tr('Brak takiej rasy w bazie.')
                          : tr('Brak ras z tą kategorią dla wybranej aktywności.'),
                      style: TextStyle(color: K9.muted),
                    ),
                  ),
                for (final b in list)
                  ListTile(
                    title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_subtitle(b), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_fitOf(b) != null) FitBadge(_fitOf(b)!),
                        const Icon(Icons.chevron_right_rounded, color: K9.faint),
                      ],
                    ),
                    onTap: () => openBreed(context, b),
                  ),
              ],
            ),
          ),
          if (sport != null) ...[
            gap12,
            Text(
              tr(
                'Kategoria opisuje rasę, a nie konkretnego psa. Przed treningiem sportowym skonsultuj się z weterynarzem.',
              ),
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(Breed b) {
    final i = breedInfoFor(b.id);
    final g = tr('Grupa {0}', [romanNumerals[b.fciGroup - 1]]);
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
    final p = breedProfileFor(breed.id);
    final dog = AppStore.instance.dog;
    final isMine = dog != null && currentDogBreed?.id == breed.id;
    return Scaffold(
      appBar: AppBar(title: Text(tr('O rasie'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          K9Card(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1A0C), K9.card],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(breed.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (p != null && p.intlName != breed.name)
                  Text(
                    p.intlName,
                    style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13.5, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 2),
                Text(fciGroupLabel(breed.fciGroup), style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13)),
                if (p != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr('Użytkowość: {0}', [p.role.label]),
                    style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13),
                  ),
                ],
                if (i?.fciNo != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Pill(icon: Icons.menu_book_rounded, text: tr('Wzorzec FCI nr {0}', [i!.fciNo])),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: i.fciUrl(breed.fciGroup)!));
                          if (context.mounted) toast(context, tr('Skopiowano link do wzorca FCI'));
                        },
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: Text(tr('Kopiuj link')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          gap12,
          if (i == null)
            K9Card(
              child: Text(tr('Dla tej rasy nie mamy jeszcze szczegółowych danych.'), style: TextStyle(color: K9.muted)),
            )
          else ...[
            K9Card(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatValue(
                          label: tr('Wzrost w kłębie'),
                          value: i.heightLabel.replaceAll(' cm', ''),
                          unit: 'cm',
                        ),
                      ),
                      Expanded(
                        child: StatValue(
                          label: tr('Masa ciała'),
                          value: i.weightLabel.replaceAll(' kg', ''),
                          unit: 'kg',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: StatValue(
                          label: tr('Długość życia'),
                          value: '${i.lifeMin}–${i.lifeMax}',
                          unit: tr('lat'),
                        ),
                      ),
                      Expanded(
                        child: StatValue(label: tr('Wielkość'), value: i.size.label),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isMine && dog.weightKg != null) ...[gap12, _DogVsBreed(dog: dog, info: i)],
            gap12,
            K9Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(tr('Potrzeba ruchu'), icon: Icons.bolt_rounded),
                  Row(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(i.energyLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(i.energyHint, style: const TextStyle(color: K9.muted, fontSize: 13)),
                ],
              ),
            ),
            if (p != null && p.bodyNotes.isNotEmpty) ...[gap12, _BodyNotes(notes: p.bodyNotes)],
            gap12,
            _SportSection(breedId: breed.id),
            gap12,
            _TrainingStart(breedId: breed.id, info: i, profile: p),
            gap12,
            K9Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(tr('Zalecane badania'), icon: Icons.health_and_safety_outlined),
                  for (final kind in TestKind.values)
                    if (i.testKeys.any((t) => testKindOf(t) == kind)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Text(
                          kind.label,
                          style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                      for (final t in i.testKeys.where((t) => testKindOf(t) == kind))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 92,
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  tr(t),
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: K9.orange),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  tr(testDescriptions[t] ?? ''),
                                  style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  const SizedBox(height: 6),
                  Text(
                    tr('Predyspozycja rasy nie oznacza, że pies zachoruje – to wskazówka, na co zwracać uwagę.'),
                    style: TextStyle(color: K9.faint, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'Wymagania programów hodowlanych różnią się między krajami i klubami – sprawdź regulamin klubu rasy.',
                    ),
                    style: TextStyle(color: K9.faint, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Przed kryciem i przy zakupie szczenięcia pytaj o wyniki tych badań u rodziców.'),
                    style: TextStyle(color: K9.faint, fontSize: 12),
                  ),
                ],
              ),
            ),
            gap12,
            Text(
              tr(
                'Dane orientacyjne – zakres dla suk i psów razem. Dokładne wymagania podaje wzorzec rasy FCI i klub rasy.',
              ),
              style: TextStyle(color: K9.faint, fontSize: 12),
            ),
          ],
        ],
      ),
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
        ? (tr('poniżej typowej masy rasy'), K9.yellow)
        : w > info.weightMax
        ? (tr('powyżej typowej masy rasy'), K9.yellow)
        : (tr('w typowym zakresie rasy'), K9.green);
    final young = dog.birthDate != null && DateTime.now().difference(dog.birthDate!).inDays < 365;
    return K9Card(
      child: Row(
        children: [
          IconBadge(Icons.monitor_weight_outlined, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('{0}: {1} kg', [dog.name, fmtNum(w)]), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  young ? tr('Szczenię jeszcze rośnie – porównuj po 12. miesiącu.') : tr('Masa {0}.', [text]),
                  style: const TextStyle(color: K9.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Oznaczenie kategorii predyspozycji: litera + ikona + kolor.
class FitBadge extends StatelessWidget {
  final Fit fit;
  final bool showLabel;
  const FitBadge(this.fit, {super.key, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${fit.letter} – ${fit.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: fit.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fit.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fit.icon, size: 14, color: fit.color),
            const SizedBox(width: 4),
            Text(
              showLabel ? '${fit.letter} · ${fit.label}' : fit.letter,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: fit.color),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyNotes extends StatelessWidget {
  final List<String> notes;
  const _BodyNotes({required this.notes});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(tr('Budowa i zdrowie – na co uważać'), icon: Icons.report_gmailerrorred_rounded),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.chevron_right_rounded, size: 16, color: K9.orange),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(n, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sekcja „Predyspozycje sportowe” – aktywności pogrupowane w kategorie.
class _SportSection extends StatefulWidget {
  final String breedId;
  const _SportSection({required this.breedId});
  @override
  State<_SportSection> createState() => _SportSectionState();
}

class _SportSectionState extends State<_SportSection> {
  bool showIndividual = false;

  @override
  Widget build(BuildContext context) {
    final fits = sportFitsFor(widget.breedId);
    if (fits.isEmpty) return const SizedBox.shrink();
    final individual = fits.where((f) => f.fit == Fit.d).toList();
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(tr('Predyspozycje sportowe'), icon: Icons.emoji_events_outlined),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in Fit.values) FitBadge(f, showLabel: true)]),
          const SizedBox(height: 8),
          for (final cat in ActivityCategory.values)
            if (fits.any((f) => f.fit != Fit.d && f.activity.categories.first == cat)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Row(
                  children: [
                    Icon(cat.icon, size: 16, color: K9.muted),
                    const SizedBox(width: 6),
                    Text(
                      cat.label,
                      style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              for (final f
                  in (fits.where((f) => f.fit != Fit.d && f.activity.categories.first == cat).toList()
                    ..sort((a, b) => a.fit.index - b.fit.index)))
                _FitRow(f),
            ],
          if (individual.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => showIndividual = !showIndividual),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    FitBadge(Fit.d),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('Indywidualna ocena ({0}): {1}', [
                          individual.length,
                          individual.map((f) => f.activity.name).join(', '),
                        ]),
                        style: const TextStyle(fontSize: 13, color: Color(0xFFCFCFD4)),
                      ),
                    ),
                    Icon(showIndividual ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: K9.muted),
                  ],
                ),
              ),
            ),
            if (showIndividual)
              for (final f in individual) _FitRow(f),
          ],
          const SizedBox(height: 10),
          Text(
            tr(
              'Kategoria opisuje rasę, a nie konkretnego psa. Przed treningiem sportowym skonsultuj się z weterynarzem.',
            ),
            style: TextStyle(color: K9.faint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FitRow extends StatelessWidget {
  final SportFit f;
  const _FitRow(this.f);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(f.activity.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              FitBadge(f.fit, showLabel: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(f.reason, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
          for (final l in f.limits)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.warning_amber_rounded, size: 14, color: K9.muted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l, style: const TextStyle(color: K9.muted, fontSize: 12.5, height: 1.3)),
                  ),
                ],
              ),
            ),
          if (f.needsConditioning)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.fitness_center_rounded, size: 14, color: K9.muted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('Wymaga stopniowego przygotowania kondycyjnego.'),
                      style: const TextStyle(color: K9.muted, fontSize: 12.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Kiedy zacząć trening – zależnie od tempa wzrostu rasy i rodzaju wysiłku.
class _TrainingStart extends StatelessWidget {
  final String breedId;
  final BreedInfo info;
  final BreedProfile? profile;
  const _TrainingStart({required this.breedId, required this.info, required this.profile});

  @override
  Widget build(BuildContext context) {
    final g = growthClassOf(info, profile);
    final rows = <(String, Set<ActivityLoad>)>[
      (tr('Bieg ciągły (canicross, dogtrekking)'), {ActivityLoad.running}),
      (tr('Praca pociągowa (bikejoring, zaprzęgi, weight pulling)'), {ActivityLoad.pulling, ActivityLoad.strength}),
      (tr('Skoki i gwałtowne zwroty (agility, flyball, frisbee, sprint)'), {ActivityLoad.jumping, ActivityLoad.sprint}),
    ];
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(tr('Kiedy zacząć trening'), icon: Icons.schedule_rounded),
          Text(
            tr('Tempo dojrzewania: {0}.', [g.label]),
            style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 10),
          _row(tr('Swobodna aktywność i zabawa'), tr('od szczenięcia, w tempie wybranym przez psa'), false),
          for (final (label, loads) in rows)
            _row(
              label,
              hasRecommended(breedId, loads)
                  ? startAgeLabel(startAgeFor(g, loads.first))
                  : tr('niezalecane dla tej rasy'),
              !hasRecommended(breedId, loads),
            ),
          const SizedBox(height: 8),
          Text(
            tr(
              'To orientacyjny wiek, a nie zgoda na trening. Decyzję podejmij z weterynarzem po ocenie stawów (np. RTG) i zacznij od krótkich, stopniowo wydłużanych sesji. Regulaminy zawodów mają własne minimalne wieki.',
            ),
            style: TextStyle(color: K9.faint, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, bool warn) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        Text(value, style: TextStyle(color: warn ? K9.muted : K9.orange, fontSize: 13)),
      ],
    ),
  );
}

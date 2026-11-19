import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../breeds/breed_screen.dart';
import '../champ_rules.dart';
import '../dogs/dog_profiles.dart';
import '../dogs/dog_switcher.dart';
import '../models.dart';
import '../notifications.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../modules/dog_profile_fields.dart';
import '../modules/modules_ui.dart';
import '../modules/module_routes.dart';
import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../ui_prefs.dart';
import 'shell.dart';
import '../modules/premium_screen.dart';
import 'forms.dart';
import 'stats.dart';
import '../l10n/l10n.dart';
import '../l10n/language_picker.dart';

/// Zakładka Pies: tylko informacje o psie, w stałych sekcjach.
/// Ustawienia aplikacji, Premium i moduły są na osobnym ekranie (ikona koła zębatego).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([s, modulesListenable]),
      builder: (context, _) {
        final dog = s.dog!;
        final ms = ModuleStore.instance;
        List<AppModule> on(List<AppModule> l) => [for (final m in l) if (ms.isEnabled(m)) m];
        final training = on([for (final m in AppModule.values) if (m.section == ModuleSection.training) m])
            .where((m) => !_specialised.contains(m))
            .toList();
        return SafeArea(
          bottom: false,
          child: ListView(
            key: PageStorageKey('profile-${DogProfiles.instance.activeId}'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Row(children: [
                Expanded(
                    child: Text(tr('Profil psa'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
                IconButton(
                  onPressed: () => showDogSwitcher(context),
                  tooltip: tr('Moje psy'),
                  icon: const Icon(Icons.swap_horiz_rounded, color: K9.orange),
                ),
                IconButton(
                  onPressed: () => openAppSettings(context),
                  tooltip: tr('Ustawienia aplikacji'),
                  icon: const Icon(Icons.settings_outlined, color: K9.orange),
                ),
              ]),
              gap12,
              _PhotoCard(dog: dog),
              gap16,
              _BasicData(dog: dog),
              gap12,
              _Measurements(dog: dog, s: s),
              _ModuleSection(
                title: tr('Zdrowie'),
                icon: Icons.favorite_border_rounded,
                tiles: [
                  _Tile(Icons.favorite_rounded, tr('Wszystkie wpisy'), () => goToTab(2)),
                  for (final m in on([AppModule.vaccinations, AppModule.deworming])) _Tile.module(context, m),
                ],
              ),
              _ModuleSection(
                title: tr('Żywienie'),
                icon: Icons.restaurant_rounded,
                tiles: [for (final m in on([AppModule.feeding, AppModule.foodStock])) _Tile.module(context, m)],
              ),
              _ModuleSection(
                title: tr('Dokumenty, galeria i notatki'),
                icon: Icons.folder_open_rounded,
                tiles: [
                  for (final m in on([AppModule.documents, AppModule.gallery])) _Tile.module(context, m),
                  _Tile(Icons.sticky_note_2_rounded, tr('Notatki'), () => _openNotes(context, dog)),
                ],
              ),
              _ModuleSection(
                title: tr('Rozród i cieczka'),
                icon: Icons.water_drop_outlined,
                tiles: [
                  for (final m in on([AppModule.heat, AppModule.breeding, AppModule.reproduction, AppModule.breedingDocs]))
                    _Tile.module(context, m),
                ],
              ),
              _ModuleSection(
                title: tr('Wystawy i pozostałe'),
                icon: Icons.emoji_events_outlined,
                tiles: [
                  for (final m in on([
                    AppModule.shows,
                    AppModule.evaluations,
                    AppModule.walks,
                    AppModule.calendar,
                    AppModule.goals,
                    AppModule.gear,
                    AppModule.breedAtlas,
                  ]))
                    _Tile.module(context, m),
                  for (final m in training) _Tile.module(context, m),
                ],
              ),
              gap12,
              K9Card(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ListRow(
                  icon: Icons.settings_outlined,
                  color: K9.orange,
                  title: tr('Ustawienia aplikacji'),
                  subtitle: tr('Język, powiadomienia, moduły, Premium, psy'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: K9.muted),
                  onTap: () => openAppSettings(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Moduły wystaw i rozrodu są już w swoich sekcjach – nie dublujemy ich.
const _specialised = {AppModule.shows, AppModule.evaluations, AppModule.reproduction, AppModule.breedingDocs};

void _openNotes(BuildContext context, Dog dog) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Notatki'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [DogNotesEditor(dog: dog)]),
      ),
    ));

/// Ustawienia aplikacji jako osobny ekran.
void openAppSettings(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Ustawienia aplikacji'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: const [_Settings()]),
      ),
    ));

class _PhotoCard extends StatelessWidget {
  final Dog dog;
  const _PhotoCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(K9.radius),
      child: SizedBox(
        height: 180,
        child: Stack(fit: StackFit.expand, children: [
          Hero(tag: 'dog-photo', child: DogPhoto(dog: dog)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xEE0B0B0C), Color(0x330B0B0C)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 72, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Row(children: [
                Flexible(
                  child: Text(dog.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Icon(dog.female ? Icons.female_rounded : Icons.male_rounded, color: K9.orange),
              ]),
              if (dog.breed.isNotEmpty)
                Text(dog.breed,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 14)),
            ]),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: IconButton.filled(
              tooltip: tr('Zmień zdjęcie'),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () => pickDogPhoto(context, dog),
              icon: const Icon(Icons.photo_camera_outlined, color: K9.text),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Nagłówek sekcji profilu: ikona, tytuł i opcjonalny przycisk.
class _SectionHead extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHead(this.icon, this.title, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, color: K9.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
              child: Text(action!, style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
            ),
        ]),
      );
}

class _BasicData extends StatelessWidget {
  final Dog dog;
  const _BasicData({required this.dog});

  @override
  Widget build(BuildContext context) {
    final breed = currentDogBreed;
    final rows = <(IconData, String, String)>[
      (dog.female ? Icons.female_rounded : Icons.male_rounded, tr('Płeć'), dog.sexLabel),
      (Icons.health_and_safety_outlined, tr('Rozród'), dog.reproLabel),
      (
        Icons.cake_outlined,
        tr('Urodzony'),
        dog.birthDate == null ? '—' : [fmtDate(dog.birthDate!), dog.ageLabel].where((e) => e.isNotEmpty).join(' · ')
      ),
      (Icons.local_fire_department_outlined, tr('Aktywność'), dog.activity?.label ?? '—'),
      (Icons.flag_circle_outlined, tr('Cel użytkowania'), dog.purpose?.label ?? '—'),
      (Icons.route_outlined, tr('Cel tygodniowy'), tr('{0} km', [fmtKm(dog.weeklyKmGoal)])),
      (Icons.memory_rounded, tr('Nr chipa'), dog.chip.isEmpty ? '—' : dog.chip),
      (Icons.badge_outlined, tr('Nr rodowodu'), dog.pedigree.isEmpty ? '—' : dog.pedigree),
      (Icons.category_outlined, tr('Grupa FCI'), dog.fciGroup == null ? '—' : tr('Grupa {0}', [romanNumerals[dog.fciGroup! - 1]])),
    ];
    return K9Card(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Column(children: [
        _SectionHead(Icons.badge_outlined, tr('Dane podstawowe'),
            action: tr('Edytuj'),
            onAction: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => DogEditScreen(existing: dog)))),
        for (final (i, r) in rows.indexed) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 9, 8, 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.$1, size: 19, color: K9.muted),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: Text(r.$2, style: const TextStyle(color: Color(0xFFCFCFD4)))),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(r.$3, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          if (i < rows.length - 1) const Divider(height: 1, color: K9.border),
        ],
        if (breed != null)
          ListRow(
            icon: Icons.menu_book_rounded,
            color: K9.orange,
            title: tr('O rasie'),
            subtitle: tr('Wzorzec FCI, masa, ruch, sporty i badania'),
            trailing: const Icon(Icons.chevron_right_rounded, color: K9.muted),
            onTap: () => openBreed(context, breed),
          ),
      ]),
    );
  }
}

class _Measurements extends StatelessWidget {
  final Dog dog;
  final AppStore s;
  const _Measurements({required this.dog, required this.s});

  @override
  Widget build(BuildContext context) {
    String bcs(int b) => b < 4 ? tr('szczupły') : (b <= 5 ? tr('optymalna') : tr('nadwaga'));
    return K9Card(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _SectionHead(Icons.monitor_weight_outlined, tr('Pomiary i masa ciała'))),
          IconButton(
            tooltip: tr('Dodaj pomiar'),
            onPressed: () => openWeightForm(context),
            icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Wrap(runSpacing: 10, children: [
            FractionallySizedBox(
                widthFactor: 0.5,
                child: StatValue(
                    label: tr('Waga'), value: dog.weightKg == null ? '—' : fmtNum(dog.weightKg!), unit: 'kg')),
            FractionallySizedBox(
                widthFactor: 0.5,
                child: StatValue(
                    label: tr('Docelowa'),
                    value: dog.targetWeightKg == null ? '—' : fmtNum(dog.targetWeightKg!),
                    unit: 'kg')),
            FractionallySizedBox(
                widthFactor: 0.5,
                child: StatValue(
                    label: tr('W kłębie'), value: dog.heightCm == null ? '—' : '${dog.heightCm!.round()}', unit: 'cm')),
            FractionallySizedBox(
                widthFactor: 0.5,
                child: StatValue(
                    label: dog.bcs == null ? tr('BCS') : bcs(dog.bcs!), value: dog.bcs == null ? '—' : '${dog.bcs}', unit: '/9')),
          ]),
        ),
        if (s.weights.length >= 2) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(height: 130, child: WeightChart(weights: s.weights, target: dog.targetWeightKg)),
          ),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(tr('Historia masy'))),
              body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [WeightHistory(s: s)]),
            ),
          )),
          icon: const Icon(Icons.show_chart_rounded),
          label: Text(tr('Wszystkie pomiary ({0})', [s.weights.length])),
        ),
      ]),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile(this.icon, this.label, this.onTap);
  _Tile.module(BuildContext context, AppModule m)
      : icon = m.icon,
        label = m.label,
        onTap = (() => openModule(context, m));
}

/// Sekcja z kafelkami funkcji. Bez włączonych funkcji – sekcja znika.
class _ModuleSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_Tile> tiles;
  const _ModuleSection({required this.title, required this.icon, required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final rows = <List<_Tile>>[for (var i = 0; i < tiles.length; i += 4) tiles.sublist(i, (i + 4).clamp(0, tiles.length))];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: K9Card(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SectionHead(icon, title),
          for (final (ri, r) in rows.indexed) ...[
            if (ri > 0) const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: i < r.length
                      ? LabeledTile(icon: r[i].icon, label: r[i].label, onTap: r[i].onTap)
                      : const SizedBox(),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

Future<void> pickDogPhoto(BuildContext context, Dog dog) async {
  try {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 900, maxHeight: 900, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    dog.photoBase64 = base64Encode(bytes);
    if (!context.mounted) return;
    if (!await saveGuarded(context, () => AppStore.instance.saveDog(dog))) return;
  } catch (e) {
    if (context.mounted) toast(context, tr('Nie udało się wczytać zdjęcia'));
  }
}

class WeightHistory extends StatelessWidget {
  final AppStore s;
  const WeightHistory({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final w = s.weights.reversed.toList();
    return Column(children: [
      if (s.weights.length >= 2)
        K9Card(child: SizedBox(height: 170, child: WeightChart(weights: s.weights, target: s.dog?.targetWeightKg))),
      gap12,
      K9Card(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(tr('Pomiary'), style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
                onPressed: () => openWeightForm(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Dodaj'))),
          ]),
          if (w.isEmpty) Padding(padding: EdgeInsets.all(8), child: Text(tr('Brak pomiarów'), style: TextStyle(color: K9.muted))),
          for (final e in w.take(12))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('{0} kg', [fmtNum(e.kg)]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(fmtDate(e.date), style: const TextStyle(color: K9.muted)),
              trailing: IconButton(tooltip: tr('Usuń'), 
                icon: const Icon(Icons.delete_outline_rounded, color: K9.faint, size: 20),
                onPressed: () async {
                  if (await confirmDelete(context, tr('pomiar {0} kg', [fmtNum(e.kg)]))) s.deleteWeight(e);
                },
              ),
            ),
        ]),
      ),
    ]);
  }
}

class DogNotesEditor extends StatefulWidget {
  final Dog dog;
  const DogNotesEditor({super.key, required this.dog});
  @override
  State<DogNotesEditor> createState() => _DogNotesEditorState();
}

class _DogNotesEditorState extends State<DogNotesEditor> {
  late final c = TextEditingController(text: widget.dog.notes);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: c,
        maxLines: 10,
        minLines: 5,
        decoration: InputDecoration(
            hintText: tr('Charakter, mocne strony, nad czym pracujemy, dieta…'), alignLabelWithHint: true),
      ),
      gap12,
      FilledButton(
        onPressed: () async {
          widget.dog.notes = c.text;
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => AppStore.instance.saveDog(widget.dog))) return;
          if (context.mounted) toast(context, tr('Notatki zapisane'));
        },
        child: Text(tr('Zapisz notatki')),
      ),
    ]);
  }
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return K9Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(children: [
        const LanguageRow(),
        if (Notifications.instance.supported)
          ListRow(
            icon: Icons.notifications_active_outlined,
            color: K9.orange,
            title: tr('Włącz powiadomienia'),
            subtitle: tr('Przypomnienia o szczepieniach i treningach'),
            onTap: () async {
              await Notifications.instance.requestPermission();
              await Notifications.instance.reschedule(s);
              if (context.mounted) toast(context, tr('Przypomnienia zaplanowane'));
            },
          ),
        ListRow(
          icon: Icons.pets_rounded,
          color: K9.orange,
          title: tr('Moje psy'),
          subtitle: tr('Przełącz psa albo dodaj kolejnego'),
          onTap: () => showDogSwitcher(context),
        ),
        ListRow(
          icon: Icons.dashboard_customize_outlined,
          color: K9.blue,
          title: tr('Moduły'),
          subtitle: tr('Włącz lub wyłącz funkcje aplikacji'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModulesSettingsScreen())),
        ),
        ListRow(
          icon: Icons.workspace_premium_outlined,
          color: K9.gold,
          title: tr('Premium'),
          subtitle: tr('Moduł hodowlany i funkcje dla zaawansowanych'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
        ),
        ListRow(
          icon: Icons.restart_alt_rounded,
          color: K9.red,
          title: tr('Usuń profil psa'),
          subtitle: tr('Usuwa tego psa i wszystkie jego wpisy'),
          onTap: () async {
            final name = s.dog?.name ?? '';
            final id = DogProfiles.instance.activeId;
            if (await confirmDelete(context, tr('{0} – profil, treningi i wszystkie wpisy', [name]))) {
              if (!context.mounted) return;
              if (await saveGuarded(context, DogProfiles.instance.deleteActive, done: tr('Usunięto'))) {
                await UiPrefs.instance.forgetDog(id);
                if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
              }
            }
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(tr('Valkor Coach · wersja {0} · dane zapisane tylko na tym telefonie', ['0.13']),
              textAlign: TextAlign.center, style: TextStyle(color: K9.muted, fontSize: 11.5)),
        ),
      ]),
    );
  }
}

/// Tworzenie i edycja profilu psa (również przy pierwszym uruchomieniu).
class DogEditScreen extends StatefulWidget {
  final Dog? existing;
  const DogEditScreen({super.key, this.existing});
  @override
  State<DogEditScreen> createState() => _DogEditScreenState();
}

class _DogEditScreenState extends State<DogEditScreen> {
  late final Dog d = widget.existing == null ? Dog(name: '') : Dog.fromJson(widget.existing!.toJson());
  late final name = TextEditingController(text: d.name);
  late final weight = TextEditingController(text: d.weightKg == null ? '' : fmtNum(d.weightKg!));
  late final target = TextEditingController(text: d.targetWeightKg == null ? '' : fmtNum(d.targetWeightKg!));
  late final height = TextEditingController(text: d.heightCm == null ? '' : d.heightCm!.round().toString());
  late final chip = TextEditingController(text: d.chip);
  late final pedigree = TextEditingController(text: d.pedigree);
  late final weekly = TextEditingController(text: fmtKm(d.weeklyKmGoal));

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? tr('Dodaj psa') : tr('Edytuj profil'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              await pickDogPhotoInto(context, d);
              setState(() {});
            },
            child: Stack(children: [
              ClipOval(child: SizedBox(width: 120, height: 120, child: DogPhoto(dog: d))),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: K9.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.black, size: 20),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        TextField(controller: name, decoration: InputDecoration(labelText: tr('Imię psa *'))),
        gap12,
        BreedField(dog: d, onChanged: () => setState(() {})),
        gap12,
        DropdownButtonFormField<int?>(
          key: ValueKey(d.fciGroup),
          initialValue: d.fciGroup,
          isExpanded: true,
          dropdownColor: K9.cardHi,
          decoration: InputDecoration(labelText: tr('Grupa FCI (do filtrowania wystaw)')),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (var g = 1; g <= 10; g++)
              DropdownMenuItem(value: g, child: Text(fciGroupLabel(g), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => d.fciGroup = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Rasa podlega próbom pracy')),
          subtitle: Text(
              d.workingTrial == null
                  ? tr('Nie ustawiono – sprawdź w nomenklaturze FCI swojej rasy (wpływa na wymagania C.I.B.)')
                  : tr('Wpływa na wymagania do Championa Międzynarodowego'),
              style: TextStyle(color: K9.muted, fontSize: 12.5)),
          value: isWorkingTrialBreed(d) ?? false,
          onChanged: (v) => setState(() => d.workingTrial = v),
        ),
        Segmented(items: [tr('Suka'), tr('Pies')], index: d.female ? 0 : 1, onChanged: (i) => setState(() => d.female = i == 0)),
        gap16,
        DogLifestyleFields(dog: d, onChanged: () => setState(() {})),
        gap16,
        DateField(
            label: tr('Data urodzenia'), value: d.birthDate, onChanged: (v) => setState(() => d.birthDate = v)),
        gap12,
        Row(children: [
          Expanded(
              child: TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Waga (kg)')))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Waga docelowa')))),
        ]),
        gap12,
        Row(children: [
          Expanded(
              child: TextField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Wzrost w kłębie (cm)')))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: d.bcs,
              dropdownColor: K9.cardHi,
              decoration: InputDecoration(labelText: tr('BCS (1–9)')),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (var i = 1; i <= 9; i++) DropdownMenuItem(value: i, child: Text('$i/9')),
              ],
              onChanged: (v) => d.bcs = v,
            ),
          ),
        ]),
        gap12,
        TextField(controller: chip, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Numer chipa'))),
        gap12,
        TextField(controller: pedigree, decoration: InputDecoration(labelText: tr('Numer rodowodu'))),
        gap12,
        TextField(
            controller: weekly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Cel tygodniowy (km)'))),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) {
              toast(context, tr('Podaj imię psa'));
              return;
            }
            d
              ..name = name.text.trim()
              ..weightKg = parseNum(weight.text)
              ..targetWeightKg = parseNum(target.text)
              ..heightCm = parseNum(height.text)
              ..chip = chip.text.trim()
              ..pedigree = pedigree.text.trim()
              ..weeklyKmGoal = parseNum(weekly.text) ?? 30;
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => AppStore.instance.saveDog(d))) return;
            await syncNutritionFromDog(d);
            if (isNew) await Notifications.instance.requestPermission();
            if (context.mounted && Navigator.of(context).canPop()) Navigator.pop(context);
          },
          child: Text(isNew ? tr('Zaczynamy') : tr('Zapisz')),
        ),
      ]),
    );
  }
}

Future<void> pickDogPhotoInto(BuildContext context, Dog dog) async {
  try {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 900, maxHeight: 900, imageQuality: 80);
    if (img == null) return;
    dog.photoBase64 = base64Encode(await img.readAsBytes());
  } catch (_) {
    if (context.mounted) toast(context, tr('Nie udało się wczytać zdjęcia'));
  }
}

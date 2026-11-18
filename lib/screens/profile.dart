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
import '../modules/premium_screen.dart';
import 'forms.dart';
import 'stats.dart';
import '../l10n/l10n.dart';
import '../l10n/language_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final dog = s.dog!;
        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
            Row(children: [
              Expanded(
                  child: Text(tr('Profil psa'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
              IconButton(
                onPressed: () => showDogSwitcher(context),
                tooltip: tr('Moje psy'),
                icon: const Icon(Icons.swap_horiz_rounded, color: K9.orange),
              ),
              IconButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => DogEditScreen(existing: dog))),
                icon: const Icon(Icons.edit_outlined, color: K9.orange),
              ),
            ]),
            gap12,
            ClipRRect(
              borderRadius: BorderRadius.circular(K9.radius),
              child: SizedBox(
                height: 220,
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
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(children: [
                            Text(dog.name,
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 6),
                            Icon(dog.female ? Icons.female_rounded : Icons.male_rounded, color: K9.orange),
                          ]),
                          SizedBox(
                            width: 200,
                            child: Text(dog.breed,
                                style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 14)),
                          ),
                        ]),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: () => pickDogPhoto(context, dog),
                      icon: const Icon(Icons.photo_camera_outlined, color: K9.text),
                    ),
                  ),
                ]),
              ),
            ),
            gap16,
            Segmented(
                items: [tr('Dane'), tr('Waga'), tr('Notatki')], index: tab, onChanged: (i) => setState(() => tab = i)),
            gap12,
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (tab) {
                0 => _DataTab(key: const ValueKey(0), dog: dog),
                1 => WeightHistory(key: const ValueKey(1), s: s),
                _ => DogNotesEditor(key: const ValueKey(2), dog: dog),
              },
            ),
            if (currentDogBreed != null) ...[
              gap12,
              K9Card(
                onTap: () => openBreed(context, currentDogBreed!),
                child: Row(children: [
                  IconBadge(Icons.menu_book_rounded, K9.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('O rasie'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text(tr('Wzorzec FCI, masa, ruch, sporty i badania'),
                          style: TextStyle(color: K9.muted, fontSize: 13)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: K9.faint),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            const AllModulesCard(),
            const SizedBox(height: 16),
            const _Settings(),
          ]),
        );
      },
    );
  }
}

Future<void> pickDogPhoto(BuildContext context, Dog dog) async {
  try {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 82);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    dog.photoBase64 = base64Encode(bytes);
    if (!context.mounted) return;
    if (!await saveGuarded(context, () => AppStore.instance.saveDog(dog))) return;
  } catch (e) {
    if (context.mounted) toast(context, tr('Nie udało się wczytać zdjęcia'));
  }
}

class _DataTab extends StatelessWidget {
  final Dog dog;
  const _DataTab({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      (dog.female ? Icons.female_rounded : Icons.male_rounded, tr('Płeć'), '${dog.sexLabel} · ${dog.reproLabel.toLowerCase()}'),
      (Icons.local_fire_department_outlined, tr('Aktywność'), dog.activity?.label ?? '—'),
      (Icons.flag_circle_outlined, tr('Cel użytkowania'), dog.purpose?.label ?? '—'),
      (Icons.cake_outlined, tr('Data urodzenia'), dog.birthDate == null ? '—' : fmtDate(dog.birthDate!)),
      (Icons.hourglass_bottom_rounded, tr('Wiek'), dog.ageLabel.isEmpty ? '—' : dog.ageLabel),
      (Icons.monitor_weight_outlined, tr('Waga'), dog.weightKg == null ? '—' : tr('{0} kg', [fmtNum(dog.weightKg!)])),
      (Icons.flag_outlined, tr('Waga docelowa'), dog.targetWeightKg == null ? '—' : tr('{0} kg', [fmtNum(dog.targetWeightKg!)])),
      (Icons.height_rounded, tr('Wysokość w kłębie'), dog.heightCm == null ? '—' : tr('{0} cm', [dog.heightCm!.round()])),
      (Icons.shield_outlined, tr('BCS (kondycja)'), dog.bcs == null ? '—' : '${dog.bcs}/9${_bcsLabel(dog.bcs!)}'),
      (Icons.memory_rounded, tr('Nr chipa'), dog.chip.isEmpty ? '—' : dog.chip),
      (Icons.badge_outlined, tr('Nr rodowodu'), dog.pedigree.isEmpty ? '—' : dog.pedigree),
      (Icons.category_outlined, tr('Grupa FCI'), dog.fciGroup == null ? '—' : tr('Grupa {0}', [romanNumerals[dog.fciGroup! - 1]])),
      (Icons.route_outlined, tr('Cel tygodniowy'), tr('{0} km', [fmtKm(dog.weeklyKmGoal)])),
    ];
    return K9Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(children: [
        for (final (i, r) in rows.indexed) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(children: [
              Icon(r.$1, size: 19, color: K9.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(r.$2, style: const TextStyle(color: Color(0xFFCFCFD4)))),
              Text(r.$3, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          if (i < rows.length - 1) const Divider(height: 1, color: K9.border),
        ],
      ]),
    );
  }

  String _bcsLabel(int b) => b < 4 ? tr(' – szczupły') : (b <= 5 ? tr(' – optymalna') : tr(' – nadwaga'));
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
              trailing: IconButton(
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
            if (await confirmDelete(context, tr('{0} – profil, treningi i wszystkie wpisy', [name]))) {
              if (!context.mounted) return;
              await saveGuarded(context, DogProfiles.instance.deleteActive);
            }
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(tr('Valkor Coach · wersja {0} · dane zapisane tylko na tym telefonie', ['0.11']),
              textAlign: TextAlign.center, style: TextStyle(color: K9.faint, fontSize: 11.5)),
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
          subtitle: Text(tr('Wpływa na wymagania do Championa Międzynarodowego'),
              style: TextStyle(color: K9.muted, fontSize: 12.5)),
          value: isWorkingTrialBreed(d),
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
        source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 82);
    if (img == null) return;
    dog.photoBase64 = base64Encode(await img.readAsBytes());
  } catch (_) {
    if (context.mounted) toast(context, tr('Nie udało się wczytać zdjęcia'));
  }
}

import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../breeds/breed_screen.dart';
import '../champ_rules.dart';
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
              const Expanded(
                  child: Text('Profil psa', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
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
                items: const ['Dane', 'Waga', 'Notatki'], index: tab, onChanged: (i) => setState(() => tab = i)),
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
                child: const Row(children: [
                  IconBadge(Icons.menu_book_rounded, K9.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('O rasie', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Wzorzec FCI, masa, ruch, sporty i badania',
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
    await AppStore.instance.saveDog(dog);
  } catch (e) {
    if (context.mounted) toast(context, 'Nie udało się wczytać zdjęcia');
  }
}

class _DataTab extends StatelessWidget {
  final Dog dog;
  const _DataTab({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      (dog.female ? Icons.female_rounded : Icons.male_rounded, 'Płeć', '${dog.sexLabel} · ${dog.reproLabel.toLowerCase()}'),
      (Icons.local_fire_department_outlined, 'Aktywność', dog.activity?.label ?? '—'),
      (Icons.flag_circle_outlined, 'Cel użytkowania', dog.purpose?.label ?? '—'),
      (Icons.cake_outlined, 'Data urodzenia', dog.birthDate == null ? '—' : fmtDate(dog.birthDate!)),
      (Icons.hourglass_bottom_rounded, 'Wiek', dog.ageLabel.isEmpty ? '—' : dog.ageLabel),
      (Icons.monitor_weight_outlined, 'Waga', dog.weightKg == null ? '—' : '${fmtNum(dog.weightKg!)} kg'),
      (Icons.flag_outlined, 'Waga docelowa', dog.targetWeightKg == null ? '—' : '${fmtNum(dog.targetWeightKg!)} kg'),
      (Icons.height_rounded, 'Wysokość w kłębie', dog.heightCm == null ? '—' : '${dog.heightCm!.round()} cm'),
      (Icons.shield_outlined, 'BCS (kondycja)', dog.bcs == null ? '—' : '${dog.bcs}/9${_bcsLabel(dog.bcs!)}'),
      (Icons.memory_rounded, 'Nr chipa', dog.chip.isEmpty ? '—' : dog.chip),
      (Icons.badge_outlined, 'Nr rodowodu', dog.pedigree.isEmpty ? '—' : dog.pedigree),
      (Icons.category_outlined, 'Grupa FCI', dog.fciGroup == null ? '—' : 'Grupa ${romanNumerals[dog.fciGroup! - 1]}'),
      (Icons.route_outlined, 'Cel tygodniowy', '${fmtKm(dog.weeklyKmGoal)} km'),
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

  String _bcsLabel(int b) => b < 4 ? ' – szczupły' : (b <= 5 ? ' – optymalna' : ' – nadwaga');
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
            const Expanded(child: Text('Pomiary', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
                onPressed: () => openWeightForm(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Dodaj')),
          ]),
          if (w.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Brak pomiarów', style: TextStyle(color: K9.muted))),
          for (final e in w.take(12))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${fmtNum(e.kg)} kg', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(fmtDate(e.date), style: const TextStyle(color: K9.muted)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: K9.faint, size: 20),
                onPressed: () async {
                  if (await confirmDelete(context, 'pomiar ${fmtNum(e.kg)} kg')) s.deleteWeight(e);
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
        decoration: const InputDecoration(
            hintText: 'Charakter, mocne strony, nad czym pracujemy, dieta…', alignLabelWithHint: true),
      ),
      gap12,
      FilledButton(
        onPressed: () async {
          widget.dog.notes = c.text;
          await AppStore.instance.saveDog(widget.dog);
          if (context.mounted) toast(context, 'Notatki zapisane');
        },
        child: const Text('Zapisz notatki'),
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
        if (Notifications.instance.supported)
          ListRow(
            icon: Icons.notifications_active_outlined,
            color: K9.orange,
            title: 'Włącz powiadomienia',
            subtitle: 'Przypomnienia o szczepieniach i treningach',
            onTap: () async {
              await Notifications.instance.requestPermission();
              await Notifications.instance.reschedule(s);
              if (context.mounted) toast(context, 'Przypomnienia zaplanowane');
            },
          ),
        ListRow(
          icon: Icons.dashboard_customize_outlined,
          color: K9.blue,
          title: 'Moduły',
          subtitle: 'Włącz lub wyłącz funkcje aplikacji',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModulesSettingsScreen())),
        ),
        ListRow(
          icon: Icons.workspace_premium_outlined,
          color: K9.gold,
          title: 'Premium',
          subtitle: 'Moduł hodowlany i funkcje dla zaawansowanych',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
        ),
        ListRow(
          icon: Icons.restart_alt_rounded,
          color: K9.red,
          title: 'Usuń wszystkie dane',
          subtitle: 'Zacznij od nowa z innym psem',
          onTap: () async {
            if (await confirmDelete(context, 'wszystkie dane psa, treningi i wpisy')) {
              await s.resetAll();
            }
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('Valkor Coach · wersja 0.9 · dane zapisane tylko na tym telefonie',
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
      appBar: AppBar(title: Text(isNew ? 'Dodaj psa' : 'Edytuj profil')),
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
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Imię psa *')),
        gap12,
        BreedField(dog: d, onChanged: () => setState(() {})),
        gap12,
        DropdownButtonFormField<int?>(
          key: ValueKey(d.fciGroup),
          initialValue: d.fciGroup,
          isExpanded: true,
          dropdownColor: K9.cardHi,
          decoration: const InputDecoration(labelText: 'Grupa FCI (do filtrowania wystaw)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (var g = 1; g <= 10; g++)
              DropdownMenuItem(value: g, child: Text(fciGroupLabel(g), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => d.fciGroup = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rasa podlega próbom pracy'),
          subtitle: const Text('Wpływa na wymagania do Championa Międzynarodowego',
              style: TextStyle(color: K9.muted, fontSize: 12.5)),
          value: isWorkingTrialBreed(d),
          onChanged: (v) => setState(() => d.workingTrial = v),
        ),
        Segmented(items: const ['Suka', 'Pies'], index: d.female ? 0 : 1, onChanged: (i) => setState(() => d.female = i == 0)),
        gap16,
        DogLifestyleFields(dog: d, onChanged: () => setState(() {})),
        gap16,
        DateField(
            label: 'Data urodzenia', value: d.birthDate, onChanged: (v) => setState(() => d.birthDate = v)),
        gap12,
        Row(children: [
          Expanded(
              child: TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Waga (kg)'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Waga docelowa'))),
        ]),
        gap12,
        Row(children: [
          Expanded(
              child: TextField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Wzrost w kłębie (cm)'))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: d.bcs,
              dropdownColor: K9.cardHi,
              decoration: const InputDecoration(labelText: 'BCS (1–9)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (var i = 1; i <= 9; i++) DropdownMenuItem(value: i, child: Text('$i/9')),
              ],
              onChanged: (v) => d.bcs = v,
            ),
          ),
        ]),
        gap12,
        TextField(controller: chip, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Numer chipa')),
        gap12,
        TextField(controller: pedigree, decoration: const InputDecoration(labelText: 'Numer rodowodu')),
        gap12,
        TextField(
            controller: weekly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cel tygodniowy (km)')),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) {
              toast(context, 'Podaj imię psa');
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
            await AppStore.instance.saveDog(d);
            await syncNutritionFromDog(d);
            if (isNew) await Notifications.instance.requestPermission();
            if (context.mounted && Navigator.of(context).canPop()) Navigator.pop(context);
          },
          child: Text(isNew ? 'Zaczynamy' : 'Zapisz'),
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
    if (context.mounted) toast(context, 'Nie udało się wczytać zdjęcia');
  }
}

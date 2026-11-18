import 'package:material_ui/material_ui.dart';

import '../breeds/breeds.dart';
import '../models.dart';
import '../nutrition/nutrition_models.dart';
import '../nutrition/nutrition_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../l10n/l10n.dart';

/// Ustawia rasę psa (z bazy, mieszaniec lub wpisaną ręcznie).
void applyBreed(Dog d, {Breed? breed, String? custom, bool mixed = false}) {
  if (mixed) {
    d
      ..mixed = true
      ..breedId = null
      ..breed = mixedBreedName
      ..fciGroup = null;
  } else if (breed != null) {
    d
      ..mixed = false
      ..breedId = breed.id
      ..breed = breed.name
      ..fciGroup = breed.fciGroup;
  } else {
    final name = (custom ?? '').trim();
    d
      ..mixed = false
      ..breedId = breedByName(name)?.id
      ..breed = name;
    final g = guessFciGroup(name);
    if (g != null) d.fciGroup = g;
  }
}

/// Pole „Rasa” z wyszukiwarką.
class BreedField extends StatelessWidget {
  final Dog dog;
  final VoidCallback onChanged;
  const BreedField({super.key, required this.dog, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = dog.breed.isEmpty ? tr('Wybierz rasę') : dog.breed;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final changed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _BreedPicker(dog: dog),
        );
        if (changed == true) onChanged();
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: tr('Rasa'),
          suffixIcon: Icon(Icons.search_rounded, color: K9.muted),
        ),
        child: Text(text, style: TextStyle(color: dog.breed.isEmpty ? K9.muted : K9.text)),
      ),
    );
  }
}

class _BreedPicker extends StatefulWidget {
  final Dog dog;
  const _BreedPicker({required this.dog});
  @override
  State<_BreedPicker> createState() => _BreedPickerState();
}

class _BreedPickerState extends State<_BreedPicker> {
  final q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final list = searchBreeds(q.text);
    final custom = q.text.trim();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(children: [
              SheetTitle(tr('Wybierz rasę')),
              TextField(
                controller: q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: tr('Szukaj, np. malinois, labrador'), prefixIcon: Icon(Icons.search_rounded)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                ListTile(
                  leading: const Icon(Icons.diversity_3_rounded, color: K9.orange),
                  title: Text(mixedBreedName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Dane tylko z tego, co wpiszesz'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
                  onTap: () {
                    applyBreed(widget.dog, mixed: true);
                    Navigator.pop(context, true);
                  },
                ),
                if (custom.isNotEmpty && !list.any((b) => b.name.toLowerCase() == custom.toLowerCase()))
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: K9.muted),
                    title: Text(tr('Użyj nazwy: „{0}”', [custom])),
                    onTap: () {
                      applyBreed(widget.dog, custom: custom);
                      Navigator.pop(context, true);
                    },
                  ),
                const Divider(color: K9.border),
                for (final b in list)
                  ListTile(
                    title: Text(b.name),
                    subtitle: Text(fciGroupLabel(b.fciGroup),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: K9.muted, fontSize: 12)),
                    trailing: widget.dog.breedId == b.id ? const Icon(Icons.check_rounded, color: K9.orange) : null,
                    onTap: () {
                      applyBreed(widget.dog, breed: b);
                      Navigator.pop(context, true);
                    },
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Wybór jednej opcji z listy w formie „kafelków”.
class ChoiceChips<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T? value;
  final String Function(T) text;
  final IconData Function(T)? icon;
  final ValueChanged<T> onChanged;
  const ChoiceChips(
      {super.key,
      required this.label,
      required this.values,
      required this.value,
      required this.text,
      required this.onChanged,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label, style: const TextStyle(color: K9.muted, fontSize: 13)),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            selected: v == value,
            onSelected: (_) => onChanged(v),
            avatar: icon == null ? null : Icon(icon!(v), size: 18, color: v == value ? Colors.black : K9.orange),
            showCheckmark: false,
            label: Text(text(v)),
            labelStyle: TextStyle(fontWeight: FontWeight.w600, color: v == value ? Colors.black : K9.text),
            selectedColor: K9.orange,
            backgroundColor: K9.card,
            side: BorderSide(color: v == value ? K9.orange : K9.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
      ]),
    ]);
  }
}

/// Pola: aktywność, cel użytkowania, status rozrodczy.
class DogLifestyleFields extends StatelessWidget {
  final Dog dog;
  final VoidCallback onChanged;
  const DogLifestyleFields({super.key, required this.dog, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChoiceChips<DogActivity>(
        label: tr('Poziom aktywności'),
        values: DogActivity.values,
        value: dog.activity,
        text: (v) => v.label,
        onChanged: (v) {
          dog.activity = v;
          onChanged();
        },
      ),
      if (dog.activity != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(dog.activity!.hint, style: const TextStyle(color: K9.faint, fontSize: 12.5)),
        ),
      gap16,
      ChoiceChips<DogPurpose>(
        label: tr('Cel użytkowania psa'),
        values: DogPurpose.values,
        value: dog.purpose,
        text: (v) => v.label,
        icon: (v) => v.icon,
        onChanged: (v) {
          dog.purpose = v;
          onChanged();
        },
      ),
      gap16,
      ChoiceChips<bool>(
        label: tr('Status rozrodczy'),
        values: const [false, true],
        value: dog.neutered,
        text: (v) => dog.female
            ? (v ? tr('Wysterylizowana') : tr('Niewysterylizowana'))
            : (v ? tr('Kastrowany') : tr('Niekastrowany')),
        onChanged: (v) {
          dog.neutered = v;
          onChanged();
        },
      ),
    ]);
  }
}

/// Przenosi kastrację i aktywność do ustawień Żywienia (dawka karmy).
Future<void> syncNutritionFromDog(Dog d) async {
  final n = NutritionStore.instance;
  final s = n.settings;
  final act = switch (d.activity) {
    DogActivity.low => ActivityLevel.low,
    DogActivity.medium => ActivityLevel.normal,
    DogActivity.high || DogActivity.veryHigh => ActivityLevel.high,
    null => s.activity,
  };
  if (s.neutered == d.neutered && s.activity == act) return;
  final j = s.toJson()
    ..['neutered'] = d.neutered
    ..['activity'] = act.name;
  await n.saveSettings(NutritionSettings.fromJson(j), reason: 'Zmiana profilu psa');
}

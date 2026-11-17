import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../notifications.dart';
import '../screens/profile.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dog_profile_fields.dart';
import 'module_store.dart';
import 'modules.dart';

/// Kreator dodawania psa krok po kroku.
class DogWizardScreen extends StatefulWidget {
  const DogWizardScreen({super.key});
  @override
  State<DogWizardScreen> createState() => _DogWizardScreenState();
}

class _DogWizardScreenState extends State<DogWizardScreen> {
  final d = Dog(name: '', activity: DogActivity.medium, purpose: DogPurpose.family);
  final name = TextEditingController();
  final weight = TextEditingController();
  final height = TextEditingController();
  final page = PageController();
  int step = 0;
  bool saving = false;

  static const titles = ['Poznajmy się', 'Wiek i budowa', 'Styl życia', 'Gotowe'];

  bool _validate() {
    if (step == 0 && name.text.trim().isEmpty) {
      toast(context, 'Podaj imię psa');
      return false;
    }
    return true;
  }

  void _go(int to) {
    FocusScope.of(context).unfocus();
    setState(() => step = to);
    page.animateToPage(to, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _collect() {
    d
      ..name = name.text.trim()
      ..weightKg = parseNum(weight.text)
      ..heightCm = parseNum(height.text);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    _collect();
    await ModuleStore.instance.resetOverrides();
    await AppStore.instance.saveDog(d);
    await syncNutritionFromDog(d);
    await Notifications.instance.requestPermission();
    if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final last = step == titles.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[step]),
        leading: step == 0 ? null : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _go(step - 1)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            for (var i = 0; i < titles.length; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                      color: i <= step ? K9.orange : K9.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ]),
        ),
        Expanded(
          child: PageView(
            controller: page,
            physics: const NeverScrollableScrollPhysics(),
            children: [_basics(), _body(), _lifestyle(), _summary()],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      if (!_validate()) return;
                      if (last) {
                        _save();
                      } else {
                        if (step == 2) _collect();
                        _go(step + 1);
                      }
                    },
              child: Text(last ? 'Zaczynamy' : 'Dalej'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _page(List<Widget> children) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: children);

  Widget _basics() => _page([
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
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Imię *'),
        ),
        gap12,
        BreedField(dog: d, onChanged: () => setState(() {})),
        gap16,
        Segmented(
            items: const ['Suka', 'Pies'], index: d.female ? 0 : 1, onChanged: (i) => setState(() => d.female = i == 0)),
      ]);

  Widget _body() => _page([
        DateField(label: 'Data urodzenia', value: d.birthDate, onChanged: (v) => setState(() => d.birthDate = v)),
        gap12,
        TextField(
            controller: weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Aktualna masa ciała (kg)')),
        gap12,
        TextField(
            controller: height,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Wysokość w kłębie (cm, opcjonalnie)')),
        gap12,
        Text(
          d.mixed
              ? 'Dla mieszańca korzystam tylko z danych, które tu wpiszesz.'
              : 'Masę możesz potem uzupełniać w Historii masy.',
          style: const TextStyle(color: K9.faint, fontSize: 12.5),
        ),
      ]);

  Widget _lifestyle() => _page([
        DogLifestyleFields(dog: d, onChanged: () => setState(() {})),
      ]);

  Widget _summary() {
    final ms = ModuleStore.instance;
    final on = AppModule.values.where((m) => m != AppModule.profile && m.autoEnabled(d, premium: ms.premium)).toList();
    final special = on.where((m) => m.rule != ModuleRule.always).toList();
    return _page([
      Text('${d.name.isEmpty ? 'Pies' : d.name} – dobieram moduły',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(
        [d.sexLabel, d.reproLabel.toLowerCase(), d.purpose?.label.toLowerCase(), d.activity == null ? null : 'aktywność: ${d.activity!.label.toLowerCase()}']
            .whereType<String>()
            .join(' · '),
        style: const TextStyle(color: K9.muted),
      ),
      gap16,
      if (special.isNotEmpty) ...[
        const Text('Specjalnie dla Twojego psa', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _chips(special, highlight: true),
        gap16,
      ],
      const Text('Dla każdego psa', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _chips(on.where((m) => m.rule == ModuleRule.always).toList()),
      gap16,
      const Text('Każdy moduł możesz później włączyć lub wyłączyć w Profil → Moduły.',
          style: TextStyle(color: K9.faint, fontSize: 12.5)),
    ]);
  }

  Widget _chips(List<AppModule> list, {bool highlight = false}) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in list)
          Pill(icon: m.icon, text: m.label),
      ].map((w) => highlight ? DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: K9.orange)),
            child: w) : w).toList());
}

import 'package:material_ui/material_ui.dart';

import '../../models.dart' show newId;
import '../../store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import 'products_screen.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

Widget _productPicker({
  required BuildContext context,
  required Set<ProductType> types,
  required FoodProduct? value,
  required ValueChanged<FoodProduct> onChanged,
  ProductType? addType,
}) {
  final list = _n.ofType(types);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (list.isEmpty)
      Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(tr('Brak produktów w bazie. Dodaj pierwszy.'), style: TextStyle(color: K9.muted)),
      ),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in list)
        ChoiceChip(
          label: Text(p.title, overflow: TextOverflow.ellipsis),
          avatar: Icon(p.type.icon, size: 18, color: p.id == value?.id ? Colors.black : p.type.color),
          selected: p.id == value?.id,
          showCheckmark: false,
          selectedColor: K9.orange,
          backgroundColor: K9.cardHi,
          side: BorderSide.none,
          labelStyle: TextStyle(color: p.id == value?.id ? Colors.black : K9.text, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => onChanged(p),
        ),
      ActionChip(
        avatar: const Icon(Icons.add_rounded, size: 18, color: K9.orange),
        label: Text(tr('Nowy')),
        backgroundColor: K9.cardHi,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onPressed: () async {
          final p = await addProductFlow(context, type: addType);
          if (p != null && types.contains(p.type)) onChanged(p);
        },
      ),
    ]),
  ]);
}

// ---------------------------------------------------------------------------
// Karmienie (posiłek, przysmak, suplement)
// ---------------------------------------------------------------------------

Future<void> openFeedingForm(BuildContext context, {FeedKind? kind, FeedingEntry? existing, DateTime? date}) =>
    showFormSheet(context, _FeedingForm(kind: kind, existing: existing, date: date));

class _FeedingForm extends StatefulWidget {
  final FeedKind? kind;
  final FeedingEntry? existing;
  final DateTime? date;
  const _FeedingForm({this.kind, this.existing, this.date});
  @override
  State<_FeedingForm> createState() => _FeedingFormState();
}

class _FeedingFormState extends State<_FeedingForm> {
  late FeedKind kind;
  FoodProduct? product;
  late DateTime date;
  final amount = TextEditingController();
  final notes = TextEditingController();
  bool byPieces = false;

  Set<ProductType> get types => switch (kind) {
        FeedKind.treat => {ProductType.treat, ProductType.other},
        FeedKind.supplement => {ProductType.supplement},
        _ => {ProductType.dry, ProductType.wet, ProductType.other},
      };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    kind = e?.kind ?? widget.kind ?? (now.hour < 13 ? FeedKind.morning : FeedKind.evening);
    date = e?.date ?? widget.date ?? now;
    notes.text = e?.notes ?? '';
    product = _n.product(e?.productId);
    if (e != null) {
      byPieces = e.pieces != null;
      amount.text = fmtNum(byPieces ? e.pieces! : e.grams, 0);
    } else {
      _defaults();
    }
  }

  void _defaults() {
    if (kind.isMeal) {
      product ??= _n.mainProduct;
      final plan = _n.plan;
      if (plan != null) {
        final g = kind == FeedKind.morning
            ? plan.morningGrams
            : kind == FeedKind.evening
                ? plan.eveningGrams
                : 0.0;
        amount.text = g > 0 ? g.round().toString() : '';
      }
      byPieces = false;
    } else {
      final list = _n.ofType(types);
      if (product == null || !types.contains(product!.type)) product = list.isEmpty ? null : list.first;
      byPieces = product?.pieceGrams != null;
      amount.text = byPieces ? '1' : '';
    }
  }

  double get _grams {
    final v = parseNum(amount.text) ?? 0;
    if (byPieces) return v * (product?.pieceGrams ?? 1);
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final kcal = product == null ? 0.0 : _grams * product!.kcalPerGram;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        widget.existing == null ? tr('Dodaj do dziennika') : tr('Wpis w dzienniku'),
        onDelete: widget.existing == null
            ? null
            : () async {
                if (!context.mounted) return;
                if (!await saveGuarded(context, () => _n.deleteEntry(widget.existing!))) {
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in FeedKind.values)
          ChoiceChip(
            label: Text(k.label),
            avatar: Icon(k.icon, size: 18, color: k == kind ? Colors.black : k.color),
            selected: k == kind,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(color: k == kind ? Colors.black : K9.text, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() {
              kind = k;
              _defaults();
            }),
          ),
      ]),
      gap16,
      _productPicker(
        context: context,
        types: types,
        value: product,
        addType: kind == FeedKind.treat
            ? ProductType.treat
            : kind == FeedKind.supplement
                ? ProductType.supplement
                : ProductType.dry,
        onChanged: (p) => setState(() {
          product = p;
          if (!kind.isMeal) byPieces = p.pieceGrams != null;
        }),
      ),
      gap16,
      Row(children: [
        Expanded(
          child: TextField(
            controller: amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: byPieces ? tr('Ilość (szt.)') : tr('Ilość (g)')),
          ),
        ),
        if (product?.pieceGrams != null) ...[
          const SizedBox(width: 10),
          Segmented(
            items: const ['g', 'szt.'],
            index: byPieces ? 1 : 0,
            onChanged: (i) => setState(() => byPieces = i == 1),
          ).sized(110),
        ],
      ]),
      if (product != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr('≈ {0} kcal', [kcal.round()]), style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
        ),
      gap12,
      DateField(label: tr('Data i godzina'), value: date, withTime: true, onChanged: (d) => setState(() => date = d!)),
      gap12,
      TextField(controller: notes, decoration: InputDecoration(labelText: tr('Notatka'))),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final g = _grams;
          if (g <= 0) {
            toast(context, tr('Podaj ilość'));
            return;
          }
          final entry = FeedingEntry(
            id: widget.existing?.id ?? newId(),
            date: date,
            kind: kind,
            productId: product?.id,
            label: product?.title ?? kind.label,
            grams: g,
            pieces: byPieces ? parseNum(amount.text) : null,
            kcal: product == null ? 0 : g * product!.kcalPerGram,
            trainingId: widget.existing?.trainingId,
            notes: notes.text.trim(),
          );
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => _n.addEntry(entry))) {
            return;
          }
          if (context.mounted) {
            Navigator.pop(context);
            final p = _n.plan;
            toast(context, p == null ? tr('Zapisano') : tr('Zapisano · do końca dnia {0} g karmy', [p.remainingGrams.round()]));
          }
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

extension on Widget {
  Widget sized(double w) => SizedBox(width: w, child: this);
}

// ---------------------------------------------------------------------------
// Worek karmy (magazyn)
// ---------------------------------------------------------------------------

Future<void> openBagForm(BuildContext context, {FoodBag? existing, FoodProduct? product}) =>
    showFormSheet(context, _BagForm(existing: existing, product: product));

class _BagForm extends StatefulWidget {
  final FoodBag? existing;
  final FoodProduct? product;
  const _BagForm({this.existing, this.product});
  @override
  State<_BagForm> createState() => _BagFormState();
}

class _BagFormState extends State<_BagForm> {
  FoodProduct? product;
  late DateTime opened;
  final kg = TextEditingController();
  final left = TextEditingController();
  final price = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    product = _n.product(b?.productId) ?? widget.product ?? _n.mainProduct;
    opened = b?.opened ?? DateTime.now();
    final g = b?.initialGrams ?? product?.packageGrams;
    kg.text = g == null ? '' : fmtNum(g / 1000, 1);
    price.text = b?.price == null ? '' : fmtNum(b!.price!, 0);
    if (b != null) left.text = fmtNum(_n.remainingIn(b) / 1000, 1);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.existing;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        b == null ? tr('Nowy worek / opakowanie') : tr('Worek karmy'),
        onDelete: b == null
            ? null
            : () async {
                if (await confirmDelete(context, tr('ten worek z magazynu'))) {
                  if (!context.mounted) return;
                  if (!await saveGuarded(context, () => _n.deleteBag(b))) {
                    return;
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      _productPicker(
        context: context,
        types: {ProductType.dry, ProductType.wet, ProductType.treat, ProductType.supplement},
        value: product,
        addType: ProductType.dry,
        onChanged: (p) => setState(() {
          product = p;
          if (p.packageGrams != null && b == null) kg.text = fmtNum(p.packageGrams! / 1000, 1);
        }),
      ),
      gap16,
      Row(children: [
        Expanded(
          child: TextField(
            controller: kg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Masa opakowania (kg)')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Cena (zł)')),
          ),
        ),
      ]),
      gap12,
      DateField(label: tr('Data otwarcia'), value: opened, onChanged: (d) => setState(() => opened = d!)),
      if (b != null) ...[
        gap12,
        TextField(
          controller: left,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: tr('Zostało w worku (kg)'), helperText: tr('Popraw, jeśli zważysz worek – prognoza się dostosuje')),
        ),
      ],
      const SizedBox(height: 20),
      if (b != null && b.active) ...[
        OutlinedButton.icon(
          onPressed: () async {
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _n.finishBag(b))) {
              return;
            }
            if (context.mounted) {
              Navigator.pop(context);
              toast(context, tr('Worek oznaczony jako skończony'));
            }
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(tr('Worek skończony')),
        ),
        const SizedBox(height: 10),
      ],
      FilledButton(
        onPressed: () async {
          final g = (parseNum(kg.text) ?? 0) * 1000;
          if (product == null || g <= 0) {
            toast(context, tr('Wybierz produkt i podaj masę'));
            return;
          }
          if (b == null) {
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _n.openBag(FoodBag(
                id: newId(), productId: product!.id, opened: opened, initialGrams: g, price: parseNum(price.text))))) {
                  return;
                }
          } else {
            b
              ..productId = product!.id
              ..opened = opened
              ..initialGrams = g
              ..price = parseNum(price.text);
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _n.upsertBag(b))) {
              return;
            }
            final l = parseNum(left.text);
            if (l != null && (l * 1000 - _n.remainingIn(b)).abs() > 1) await _n.setRemaining(b, l * 1000);
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Ustawienia żywienia
// ---------------------------------------------------------------------------

Future<void> openNutritionSettings(BuildContext context) => showFormSheet(context, const _SettingsForm());

class _SettingsForm extends StatefulWidget {
  const _SettingsForm();
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late NutritionSettings s = NutritionSettings.fromJson(_n.settings.toJson());
  late final target = TextEditingController(
      text: AppStore.instance.dog?.targetWeightKg == null ? '' : fmtNum(AppStore.instance.dog!.targetWeightKg!));

  Future<void> _time(bool morning) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: morning ? s.morningHour : s.eveningHour, minute: morning ? s.morningMinute : s.eveningMinute),
    );
    if (t == null) return;
    setState(() {
      if (morning) {
        s.morningHour = t.hour;
        s.morningMinute = t.minute;
      } else {
        s.eveningHour = t.hour;
        s.eveningMinute = t.minute;
      }
    });
  }

  String _hm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(tr('Ustawienia żywienia')),
      Text(tr('Cel'), style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Segmented(
        items: [tr('Utrzymanie'), tr('Redukcja'), tr('Masa')],
        index: s.goal.index,
        onChanged: (i) => setState(() => s.goal = NutritionGoal.values[i]),
      ),
      gap12,
      TextField(
        controller: target,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr('Waga docelowa (kg)')),
      ),
      gap16,
      Text(tr('Aktywność poza treningami'), style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Segmented(
        items: [for (final a in ActivityLevel.values) a.label],
        index: s.activity.index,
        onChanged: (i) => setState(() => s.activity = ActivityLevel.values[i]),
      ),
      const SizedBox(height: 6),
      Text(tr('{0}. Treningi z aplikacji doliczam automatycznie.', [s.activity.hint]),
          style: const TextStyle(color: K9.muted, fontSize: 12.5)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.neutered,
        onChanged: (v) => setState(() => s.neutered = v),
        title: Text(AppStore.instance.dog?.female == false ? tr('Pies wykastrowany') : tr('Suka wysterylizowana')),
      ),
      const Divider(),
      Text(tr('Karmienia'), style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _time(true),
            icon: const Icon(Icons.wb_sunny_rounded),
            label: Text(tr('Rano {0}', [_hm(s.morningHour, s.morningMinute)])),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _time(false),
            icon: const Icon(Icons.nights_stay_rounded),
            label: Text(tr('Wieczór {0}', [_hm(s.eveningHour, s.eveningMinute)])),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Text(tr('Podział porcji')),
        const Spacer(),
        Text(tr('rano {0}% · wieczór {1}%', [(s.morningShare * 100).round(), (100 - s.morningShare * 100).round()]),
            style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
      ]),
      Slider(
        value: s.morningShare,
        min: 0,
        max: 1,
        divisions: 10,
        activeColor: K9.orange,
        inactiveColor: K9.cardHi,
        onChanged: (v) => setState(() => s.morningShare = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.feedReminders,
        onChanged: (v) => setState(() => s.feedReminders = v),
        title: Text(tr('Przypomnienia o karmieniu')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.stockReminders,
        onChanged: (v) => setState(() => s.stockReminders = v),
        title: Text(tr('Przypomnienia o kończącej się karmie')),
      ),
      Row(children: [
        Expanded(child: Text(tr('Przypomnij o zakupie przed końcem worka'))),
        IconButton(
            onPressed: s.buyLeadDays > 1 ? () => setState(() => s.buyLeadDays--) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded)),
        Text(tr('{0} dni', [s.buyLeadDays]), style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
            onPressed: s.buyLeadDays < 21 ? () => setState(() => s.buyLeadDays++) : null,
            icon: const Icon(Icons.add_circle_outline_rounded)),
      ]),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () async {
          final dog = AppStore.instance.dog;
          final t = parseNum(target.text);
          if (dog != null && t != dog.targetWeightKg) {
            dog.targetWeightKg = t;
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => AppStore.instance.saveDog(dog))) {
              return;
            }
          }
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => _n.saveSettings(s))) {
            return;
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Harmonogram suplementów
// ---------------------------------------------------------------------------

Future<void> openSupplementPlanForm(BuildContext context, {SupplementPlan? existing}) =>
    showFormSheet(context, _SupplementForm(existing: existing));

class _SupplementForm extends StatefulWidget {
  final SupplementPlan? existing;
  const _SupplementForm({this.existing});
  @override
  State<_SupplementForm> createState() => _SupplementFormState();
}

class _SupplementFormState extends State<_SupplementForm> {
  late SupplementPlan s = widget.existing == null
      ? SupplementPlan(id: newId(), name: '')
      : SupplementPlan.fromJson(widget.existing!.toJson());
  late final name = TextEditingController(text: s.name);
  late final dose = TextEditingController(text: s.dose);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        widget.existing == null ? tr('Nowy suplement') : tr('Suplement'),
        onDelete: widget.existing == null
            ? null
            : () async {
                if (!context.mounted) return;
                if (!await saveGuarded(context, () => _n.deleteSupplement(widget.existing!))) {
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
      ),
      _productPicker(
        context: context,
        types: {ProductType.supplement},
        value: _n.product(s.productId),
        addType: ProductType.supplement,
        onChanged: (p) => setState(() {
          s.productId = p.id;
          name.text = p.title;
        }),
      ),
      gap12,
      TextField(controller: name, decoration: InputDecoration(labelText: tr('Nazwa'))),
      gap12,
      TextField(controller: dose, decoration: InputDecoration(labelText: tr('Dawka (np. 1 tabletka)'))),
      gap12,
      OutlinedButton.icon(
        onPressed: () async {
          final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.hour, minute: s.minute));
          if (t != null) setState(() => s..hour = t.hour..minute = t.minute);
        },
        icon: const Icon(Icons.schedule_rounded),
        label: Text(tr('Codziennie o {0}:{1}', [s.hour.toString().padLeft(2, '0'), s.minute.toString().padLeft(2, '0')])),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.active,
        onChanged: (v) => setState(() => s.active = v),
        title: Text(tr('Przypominaj')),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () async {
          s
            ..name = name.text.trim()
            ..dose = dose.text.trim();
          if (s.name.isEmpty) {
            toast(context, tr('Wpisz nazwę'));
            return;
          }
          if (!context.mounted) return;
          if (!await saveGuarded(context, () => _n.upsertSupplement(s))) {
            return;
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

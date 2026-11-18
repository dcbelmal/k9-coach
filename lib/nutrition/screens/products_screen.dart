import 'package:flutter/services.dart' show Clipboard;
import 'package:material_ui/material_ui.dart';

import '../../files/file_store.dart';
import '../../models.dart' show newId;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import '../product_lookup.dart';
import '../web_import.dart';
import 'label_capture.dart';
import 'scanner_screen.dart';
import '../../l10n/l10n.dart';

final _n = NutritionStore.instance;

/// Lokalna baza produktów (karmy, przysmaki, suplementy).
class ProductsScreen extends StatefulWidget {
  final ProductType? initialType;
  const ProductsScreen({super.key, this.initialType});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  ProductType? filter;
  String query = '';

  @override
  void initState() {
    super.initState();
    filter = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(filter == ProductType.treat ? tr('Przysmaki') : tr('Baza produktów'))),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => addProductFlow(context, type: filter),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: _n,
        builder: (context, _) {
          final q = query.toLowerCase();
          final list = _n.products
              .where((p) => filter == null || p.type == filter)
              .where((p) => q.isEmpty || p.title.toLowerCase().contains(q) || p.barcode.contains(q))
              .toList()
            ..sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: tr('Szukaj nazwy lub kodu')),
            ),
            gap12,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(tr('Wszystkie'), null),
                for (final t in ProductType.values) _chip(t.label, t),
              ]),
            ),
            gap12,
            if (list.isEmpty)
              EmptyState(
                icon: Icons.qr_code_scanner_rounded,
                title: tr('Brak produktów'),
                text: tr('Zeskanuj kod kreskowy z worka, przysmaku lub suplementu albo dodaj produkt ręcznie.'),
                action: tr('Dodaj produkt'),
                onAction: () => addProductFlow(context, type: filter),
              ),
            for (final (i, p) in list.indexed)
              FadeSlideIn(
                index: i.clamp(0, 10),
                child: Padding(padding: const EdgeInsets.only(bottom: 10), child: ProductTile(p: p)),
              ),
          ]);
        },
      ),
    );
  }

  Widget _chip(String label, ProductType? t) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: filter == t,
          showCheckmark: false,
          selectedColor: K9.orange,
          backgroundColor: K9.cardHi,
          side: BorderSide.none,
          labelStyle: TextStyle(color: filter == t ? Colors.black : K9.text, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => setState(() => filter = t),
        ),
      );
}

class ProductTile extends StatelessWidget {
  final FoodProduct p;
  final VoidCallback? onTap;
  const ProductTile({super.key, required this.p, this.onTap});

  @override
  Widget build(BuildContext context) {
    final kcal = p.kcalPer100gEffective;
    final info = <String>[
      p.type.label,
      if (kcal != null) tr('{0} kcal/100 g{1}', [kcal.round(), p.kcalEstimated ? tr(' (szac.)') : '']),
      if (p.pieceGrams != null) tr('{0} g/szt.', [fmtNum(p.pieceGrams!)]),
      if (p.packageGrams != null) fmtGrams(p.packageGrams!),
    ];
    return K9Card(
      padding: const EdgeInsets.all(12),
      onTap: onTap ?? () => openProductForm(context, existing: p),
      child: Row(children: [
        ProductThumb(p: p),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(info.join(' · '), maxLines: 2, style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          ]),
        ),
        if (p.favorite) const Icon(Icons.star_rounded, color: K9.orange, size: 20),
        if (p.id == _n.settings.mainProductId)
          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: K9.green, size: 20)),
      ]),
    );
  }
}

class ProductThumb extends StatelessWidget {
  final FoodProduct p;
  final double size;
  const ProductThumb({super.key, required this.p, this.size = 52});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: p.photo == null
              ? Container(color: p.type.color.withValues(alpha: 0.15), child: Icon(p.type.icon, color: p.type.color, size: size / 2))
              : FileStore.image(p.photo!),
        ),
      );
}

String fmtGrams(double g) => g >= 1000 ? tr('{0} kg', [fmtNum(g / 1000, g % 1000 == 0 ? 0 : 1)]) : '${g.round()} g';

// ---------------------------------------------------------------------------
// Dodawanie: skan / zdjęcie / ręcznie
// ---------------------------------------------------------------------------

/// Pełny proces dodania produktu. Zwraca zapisany produkt (lub null).
Future<FoodProduct?> addProductFlow(BuildContext context, {ProductType? type}) async {
  final choice = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetTitle(tr('Dodaj produkt')),
        ListRow(
            icon: Icons.qr_code_scanner_rounded,
            color: K9.orange,
            title: tr('Skanuj kod kreskowy lub QR'),
            subtitle: tr('Szukam w darmowych bazach produktów'),
            onTap: () => Navigator.pop(c, 0)),
        ListRow(
            icon: Icons.photo_camera_rounded,
            color: K9.blue,
            title: tr('Zdjęcie etykiety'),
            subtitle: tr('Odczytam skład, białko, tłuszcz i kcal ze zdjęcia'),
            onTap: () => Navigator.pop(c, 1)),
        ListRow(
            icon: Icons.link_rounded,
            color: K9.yellow,
            title: tr('Link ze strony producenta'),
            subtitle: tr('Wklej adres strony karmy albo skopiowany tekst'),
            onTap: () => Navigator.pop(c, 3)),
        ListRow(
            icon: Icons.edit_note_rounded,
            color: K9.green,
            title: tr('Wpisz ręcznie'),
            onTap: () => Navigator.pop(c, 2)),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case 0:
      final code = await scanCode(context);
      if (code == null || !context.mounted) return null;
      return productFromCode(context, code, type: type);
    case 1:
      final cap = await captureLabel(context);
      if (cap == null || !context.mounted) return null;
      final draft = FoodProduct(id: newId(), name: '', type: type ?? ProductType.dry, photo: cap.photo);
      toast(context, labelResultMessage(cap, applyLabel(draft, cap.values)));
      return openProductForm(context, draft: draft);
    case 3:
      final draft = FoodProduct(id: newId(), name: '', type: type ?? ProductType.dry);
      if (!await importFromWeb(context, draft) || !context.mounted) return null;
      return openProductForm(context, draft: draft);
    default:
      return openProductForm(context, draft: FoodProduct(id: newId(), name: '', type: type ?? ProductType.dry));
  }
}

/// Kod → produkt z lokalnej bazy albo z internetu, potem formularz do sprawdzenia.
Future<FoodProduct?> productFromCode(BuildContext context, String code, {ProductType? type}) async {
  final local = _n.byBarcode(code);
  if (local != null) {
    toast(context, tr('Ten produkt już jest w bazie'));
    return openProductForm(context, existing: local);
  }
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(width: 16),
        Expanded(child: Text(tr('Szukam produktu…'))),
      ]),
    ),
  );
  final res = await ProductLookup.lookup(code);
  if (!context.mounted) return null;
  Navigator.of(context).pop();
  final isEan = RegExp(r'^\d{6,14}$').hasMatch(code);
  var draft = res.product;
  if (draft == null) {
    draft = FoodProduct(id: newId(), name: isEan ? '' : code, barcode: isEan ? code : '', type: type ?? ProductType.dry);
    if (!isEan) {
      toast(context, tr('Odczytany kod QR: {0}', [code]));
      return openProductForm(context, draft: draft);
    }
    final photo = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(res.offline ? tr('Brak internetu') : tr('Nie znalazłem tej karmy')),
        content: Text(res.offline
            ? tr('Nie mogę sprawdzić kodu bez internetu. Zrób zdjęcie etykiety – odczytam wartości na telefonie.')
            : tr('Kodu {0} nie ma w darmowych bazach ({1}). Zrób zdjęcie tyłu opakowania, a odczytam skład, białko, tłuszcz i kalorie. Nazwę i producenta wpisz raz – potem ten kod rozpoznam od razu.', [code, res.checked.join(', ')])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Wpiszę ręcznie'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Zdjęcie etykiety'))),
        ],
      ),
    );
    if (!context.mounted) return null;
    if (photo == true) {
      final cap = await captureLabel(context);
      if (!context.mounted) return null;
      if (cap != null) {
        draft.photo = cap.photo;
        toast(context, labelResultMessage(cap, applyLabel(draft, cap.values)));
      }
    }
  } else {
    final missing = draft.kcalPer100g == null && draft.proteinPct == null;
    toast(
        context,
        missing
            ? tr('Znaleziono: {0}, ale bez wartości odżywczych. Dodaj zdjęcie etykiety w formularzu.', [draft.title])
            : tr('Znaleziono: {0}. Sprawdź dane.', [draft.title]));
  }
  return openProductForm(context, draft: draft);
}

/// Pyta o link (albo wklejony tekst), pobiera stronę i uzupełnia puste pola produktu.
/// Zwraca false, gdy użytkownik zrezygnował.
Future<bool> importFromWeb(BuildContext context, FoodProduct p) async {
  final ctrl = TextEditingController();
  try {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (WebImport.findUrl(clip) != null && clip.length < 500) ctrl.text = clip.trim();
  } catch (_) {}
  if (!context.mounted) return false;
  final input = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Strona producenta')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            tr('Wklej link do strony tej karmy (producent albo sklep). Możesz też wkleić skopiowany ze strony tekst ze składem i analizą.'),
            style: TextStyle(color: K9.muted)),
        gap12,
        TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: tr('Link lub tekst'),
            hintText: tr('https://…'),
            suffixIcon: IconButton(
              tooltip: tr('Wklej'),
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: () async {
                final t = (await Clipboard.getData('text/plain'))?.text;
                if (t != null) ctrl.text = t.trim();
              },
            ),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Anuluj'))),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(tr('Pobierz dane'))),
      ],
    ),
  );
  if (input == null || input.isEmpty || !context.mounted) return false;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(width: 16),
        Expanded(child: Text(tr('Czytam stronę…'))),
      ]),
    ),
  );
  final r = await WebImport.fromInput(input);
  if (!context.mounted) return true;
  Navigator.of(context).pop();
  var filled = applyLabel(p, r.values);
  if (p.name.isEmpty && r.name.isNotEmpty) {
    p.name = r.name;
    filled++;
  }
  if (p.brand.isEmpty && r.brand.isNotEmpty && r.brand.length < 30) p.brand = r.brand;
  if (p.photo == null && r.image != null) {
    try {
      p.photo = await FileStore.save(r.image!);
    } catch (_) {}
  }
  if (!context.mounted) return true;
  toast(
      context,
      !r.fetched
          ? tr('Nie udało się otworzyć strony. Sprawdź internet albo skopiuj tekst ze strony i wklej go tutaj.')
          : r.values.isEmpty
              ? tr('Na tej stronie nie znalazłem składu ani wartości. Otwórz ją w przeglądarce, skopiuj tekst „Składniki analityczne” i wklej.')
              : tr('Pobrano: {0} {1}. {2}Sprawdź dane przed zapisem.', [filled, filled == 1 ? tr('pole') : (filled < 5 ? tr('pola') : tr('pól')), p.kcalPer100g == null && p.estimatedKcalPer100g != null ? tr('Strona nie podaje kalorii – liczę je ze składu (ok. {0} kcal/100 g). Jeśli znasz dokładną wartość z worka, wpisz ją. ', [p.estimatedKcalPer100g!.round()]) : '']));
  return true;
}

Future<FoodProduct?> openProductForm(BuildContext context, {FoodProduct? existing, FoodProduct? draft}) =>
    showFormSheet<FoodProduct>(context, _ProductForm(existing: existing, draft: draft));

class _ProductForm extends StatefulWidget {
  final FoodProduct? existing;
  final FoodProduct? draft;
  const _ProductForm({this.existing, this.draft});
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late FoodProduct p;
  final name = TextEditingController(),
      brand = TextEditingController(),
      code = TextEditingController(),
      kcal = TextEditingController(),
      protein = TextEditingController(),
      fat = TextEditingController(),
      fiber = TextEditingController(),
      ash = TextEditingController(),
      moisture = TextEditingController(),
      pack = TextEditingController(),
      piece = TextEditingController(),
      comp = TextEditingController();
  bool makeMain = false;

  @override
  void initState() {
    super.initState();
    final src = widget.existing ?? widget.draft ?? FoodProduct(id: newId(), name: '');
    p = FoodProduct.fromJson(src.toJson());
    _toFields();
    makeMain = _n.settings.mainProductId == p.id || (_n.mainProduct == null && p.type.isMainFood);
  }

  void _toFields() {
    String f(double? v) => v == null ? '' : fmtNum(v, v == v.roundToDouble() ? 0 : 1);
    name.text = p.name;
    brand.text = p.brand;
    code.text = p.barcode;
    kcal.text = f(p.kcalPer100g);
    protein.text = f(p.proteinPct);
    fat.text = f(p.fatPct);
    fiber.text = f(p.fiberPct);
    ash.text = f(p.ashPct);
    moisture.text = f(p.moisturePct);
    pack.text = p.packageGrams == null ? '' : fmtNum(p.packageGrams! / 1000, 2).replaceAll(RegExp(r',?0+$'), '');
    piece.text = f(p.pieceGrams);
    comp.text = p.composition;
  }

  Future<void> _readLabel() async {
    _collect();
    final cap = await captureLabel(context, savePhoto: p.photo == null);
    if (cap == null || !mounted) return;
    final n = applyLabel(p, cap.values);
    setState(() {
      p.photo ??= cap.photo;
      _toFields();
    });
    toast(context, labelResultMessage(cap, n));
  }

  Future<void> _readWeb() async {
    _collect();
    await importFromWeb(context, p);
    if (mounted) setState(_toFields);
  }

  void _collect() {
    p
      ..name = name.text.trim()
      ..brand = brand.text.trim()
      ..barcode = code.text.trim()
      ..kcalPer100g = parseNum(kcal.text)
      ..proteinPct = parseNum(protein.text)
      ..fatPct = parseNum(fat.text)
      ..fiberPct = parseNum(fiber.text)
      ..ashPct = parseNum(ash.text)
      ..moisturePct = parseNum(moisture.text)
      ..packageGrams = parseNum(pack.text) == null ? null : parseNum(pack.text)! * 1000
      ..pieceGrams = parseNum(piece.text)
      ..composition = comp.text.trim();
  }

  Widget _num(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          onChanged: (_) => setState(_collect),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _scan() async {
    final c = await scanCode(context);
    if (c == null || !mounted) return;
    code.text = c;
    final res = await ProductLookup.lookup(c);
    if (!mounted) return;
    final found = res.product;
    if (found == null) {
      toast(context, res.offline ? tr('Brak internetu – użyj zdjęcia etykiety') : tr('Nie ma w darmowych bazach – użyj „Odczytaj z etykiety”'));
      return;
    }
    setState(() {
      if (name.text.isEmpty) name.text = found.name;
      if (brand.text.isEmpty) brand.text = found.brand;
      if (kcal.text.isEmpty && found.kcalPer100g != null) kcal.text = fmtNum(found.kcalPer100g!, 0);
      if (protein.text.isEmpty && found.proteinPct != null) protein.text = fmtNum(found.proteinPct!);
      if (fat.text.isEmpty && found.fatPct != null) fat.text = fmtNum(found.fatPct!);
      if (pack.text.isEmpty && found.packageGrams != null) pack.text = fmtNum(found.packageGrams! / 1000, 2);
      if (comp.text.isEmpty) comp.text = found.composition;
      _collect();
    });
    toast(context, tr('Uzupełniono dane z bazy online'));
  }

  @override
  Widget build(BuildContext context) {
    final est = p.estimatedKcalPer100g;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(
        widget.existing == null ? tr('Nowy produkt') : tr('Produkt'),
        onDelete: widget.existing == null
            ? null
            : () async {
                if (await confirmDelete(context, widget.existing!.title)) {
                  await _n.deleteProduct(widget.existing!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
      Row(children: [
        GestureDetector(
          onTap: () async {
            final ph = await pickPhoto(context);
            if (ph != null) setState(() => p.photo = ph);
          },
          child: p.photo == null
              ? Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: K9.cardHi, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.add_a_photo_rounded, color: K9.muted),
                )
              : ProductThumb(p: p, size: 72),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Nazwa produktu'))),
            const SizedBox(height: 8),
            TextField(controller: brand, decoration: InputDecoration(labelText: tr('Producent'))),
          ]),
        ),
      ]),
      gap12,
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ProductType.values)
          ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 18, color: t == p.type ? Colors.black : t.color),
            selected: t == p.type,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(color: t == p.type ? Colors.black : K9.text, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() => p.type = t),
          ),
      ]),
      gap12,
      TextField(
        controller: code,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: tr('Kod kreskowy (EAN)'),
          suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: K9.orange), onPressed: _scan),
        ),
      ),
      gap16,
      Row(children: [
        Expanded(child: Text(tr('Wartości z etykiety'), style: TextStyle(fontWeight: FontWeight.w700))),
        IconButton(
          tooltip: tr('Pobierz ze strony producenta'),
          onPressed: _readWeb,
          icon: const Icon(Icons.link_rounded, color: K9.yellow),
        ),
        TextButton.icon(
          onPressed: _readLabel,
          icon: const Icon(Icons.document_scanner_rounded, size: 20),
          label: Text(tr('Ze zdjęcia')),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        _num(kcal, tr('kcal / 100 g')),
        const SizedBox(width: 10),
        _num(pack, tr('Opakowanie (kg)')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _num(protein, tr('Białko %')),
        const SizedBox(width: 10),
        _num(fat, tr('Tłuszcz %')),
        const SizedBox(width: 10),
        _num(fiber, tr('Włókno %')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _num(ash, tr('Popiół %')),
        const SizedBox(width: 10),
        _num(moisture, tr('Wilgotność %')),
        const SizedBox(width: 10),
        _num(piece, tr('Sztuka (g)')),
      ]),
      if (p.kcalPer100g == null && est != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr('Szacowana kaloryczność ze składu: {0} kcal/100 g', [est.round()]),
              style: const TextStyle(color: K9.orange, fontSize: 12.5)),
        ),
      if (p.type == ProductType.treat || p.type == ProductType.supplement)
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(tr('Podaj masę jednej sztuki – wtedy w treningu wystarczy liczyć sztuki.'),
              style: TextStyle(color: K9.muted, fontSize: 12.5)),
        ),
      gap12,
      TextField(controller: comp, minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: tr('Skład'))),
      if (p.type.isMainFood)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: makeMain,
          onChanged: (v) => setState(() => makeMain = v),
          title: Text(tr('To główna karma psa')),
          subtitle: Text(tr('Z niej liczę porcję w gramach'), style: TextStyle(color: K9.muted)),
        ),
      Row(children: [
        Checkbox(value: p.favorite, onChanged: (v) => setState(() => p.favorite = v ?? false)),
        Text(tr('Ulubiony')),
      ]),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () async {
          _collect();
          if (p.name.isEmpty && p.brand.isEmpty) {
            toast(context, tr('Wpisz nazwę produktu'));
            return;
          }
          await _n.upsertProduct(p);
          if (makeMain && p.type.isMainFood && _n.settings.mainProductId != p.id) {
            final s = _n.settings;
            s.mainProductId = p.id;
            await _n.saveSettings(s, reason: 'nowa karma główna');
          }
          if (context.mounted) Navigator.pop(context, p);
        },
        child: Text(tr('Zapisz')),
      ),
    ]);
  }
}

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../files/file_store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../label_parser.dart';
import '../nutrition_models.dart';
import '../ocr/text_reader.dart';

/// Wynik zdjęcia etykiety: zapisane zdjęcie i odczytane wartości.
class LabelCapture {
  final String? photo;
  final LabelValues values;
  final bool ocrAvailable;
  const LabelCapture(this.photo, this.values, this.ocrAvailable);
}

/// Zdjęcie etykiety (aparat lub galeria) + odczyt tekstu na telefonie.
Future<LabelCapture?> captureLabel(BuildContext context, {bool savePhoto = true}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const SheetTitle('Zdjęcie etykiety'),
        const Text(
            'Sfotografuj tył opakowania: skład, „składniki analityczne” i energię (kcal). '
            'Trzymaj telefon prosto, żeby tekst był ostry i dobrze oświetlony.',
            style: TextStyle(color: K9.muted)),
        gap12,
        ListRow(
            icon: Icons.photo_camera_rounded,
            color: K9.orange,
            title: 'Zrób zdjęcie',
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListRow(
            icon: Icons.photo_library_rounded,
            color: K9.blue,
            title: 'Wybierz z galerii',
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null || !context.mounted) return null;
  XFile? img;
  try {
    img = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 90);
  } catch (_) {
    if (context.mounted) toast(context, 'Nie udało się zrobić zdjęcia');
    return null;
  }
  if (img == null || !context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(width: 16),
        Expanded(child: Text('Czytam etykietę…')),
      ]),
    ),
  );
  String? photo;
  if (savePhoto) {
    try {
      photo = await FileStore.save(await img.readAsBytes());
    } catch (_) {}
  }
  final text = TextReader.supported ? await TextReader.readFile(img.path) : null;
  if (context.mounted) Navigator.of(context).pop();
  return LabelCapture(photo, text == null ? LabelValues() : LabelParser.parse(text), TextReader.supported);
}

/// Uzupełnia puste pola produktu wartościami z etykiety. Zwraca liczbę uzupełnionych pól.
int applyLabel(FoodProduct p, LabelValues v) {
  var n = 0;
  T? fill<T>(T? cur, T? val) {
    if (cur == null && val != null) {
      n++;
      return val;
    }
    return cur;
  }

  p.kcalPer100g = fill(p.kcalPer100g, v.kcalPer100g);
  p.proteinPct = fill(p.proteinPct, v.protein);
  p.fatPct = fill(p.fatPct, v.fat);
  p.fiberPct = fill(p.fiberPct, v.fiber);
  p.ashPct = fill(p.ashPct, v.ash);
  p.moisturePct = fill(p.moisturePct, v.moisture);
  p.packageGrams = fill(p.packageGrams, v.packageGrams);
  if (p.composition.isEmpty && v.composition.isNotEmpty) {
    p.composition = v.composition;
    n++;
  }
  return n;
}

String labelResultMessage(LabelCapture c, int filled) {
  if (!c.ocrAvailable) return 'Odczyt etykiety działa tylko w aplikacji na telefonie. Zdjęcie zapisane.';
  if (c.values.isEmpty) {
    return 'Nie udało się odczytać wartości. Zrób ostrzejsze zdjęcie samej tabeli albo wpisz je ręcznie.';
  }
  if (filled == 0) return 'Odczytane wartości już były wpisane.';
  return 'Odczytano z etykiety: $filled ${filled == 1 ? 'pole' : (filled < 5 ? 'pola' : 'pól')}. Sprawdź je przed zapisem.';
}

/// Odczyt wartości z tekstu etykiety (po OCR). Funkcje czyste – łatwe do testów.
///
/// Rozumie typowe opisy po polsku, angielsku, niemiecku i francusku, np.
/// „Składniki analityczne: białko 26%, zawartość tłuszczu 16%, włókno surowe 2,5%,
/// popiół surowy 7%, wilgotność 8%. Energia metaboliczna: 3850 kcal/kg”.
class LabelValues {
  double? kcalPer100g, protein, fat, fiber, ash, moisture, packageGrams;
  String composition = '';

  int get count => [kcalPer100g, protein, fat, fiber, ash, moisture, packageGrams].where((v) => v != null).length +
      (composition.isEmpty ? 0 : 1);
  bool get isEmpty => count == 0;
}

class LabelParser {
  static const _num = r'(\d{1,3}(?:[.,]\d{1,2})?)';
  static const _gap = r'[^0-9%\n]{0,30}?';

  static LabelValues parse(String raw) {
    final v = LabelValues();
    // Ujednolicenie: małe litery, jedna spacja, poprawki częstych błędów OCR.
    final t = raw
        .toLowerCase()
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAllMapped(RegExp(r'(\d) ?[,.] ?(\d)'), (m) => '${m[1]}.${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)\s*o/o'), (m) => '${m[1]}%');
    final flat = t.replaceAll('\n', ' ');

    // Wartości procentowe szukamy najpierw w sekcji „składniki analityczne”,
    // żeby nie pomylić ich z procentami w składzie (np. „kurczak 26%”).
    final a = RegExp(
            r'składniki analityczne|skladniki analityczne|sk.adniki analityczne|analytical constituents|analytische bestandteile|constituants analytiques|analiza')
        .firstMatch(flat);
    final section = a == null ? flat : flat.substring(a.start);

    double? pct(List<String> names) {
      for (final n in names) {
        final m = RegExp('(?:^|[^a-ząćęłńóśźż])(?:$n)$_gap$_num\\s*%').firstMatch(section);
        if (m != null) {
          final x = double.tryParse(m.group(1)!.replaceAll(',', '.'));
          if (x != null && x <= 100) return x;
        }
      }
      return null;
    }

    v.protein = pct([r'białko|bialko|biatko|crude protein|protein[a-z]*|protéines?|rohprotein|eiwei[ßs]']);
    v.fat = pct([
      r'zawarto[śs][ćc] tłuszczu|zawartosc tluszczu|tłuszcz[a-z ]*|tluszcz[a-z ]*|fat content|crude fat|crude oils? and fats|oils? and fats|fat(?!ty)|matières grasses|mati[eè]res grasses brutes|fettgehalt|rohfett'
    ]);
    v.fiber = pct([r'włókno[a-z ]*|wlokno[a-z ]*|crude fib(?:re|er)s?|fib(?:re|er)s?|cellulose brute|rohfaser']);
    v.ash = pct([r'popiół[a-z ]*|popiol[a-z ]*|substancje nieorganiczne|crude ash|inorganic matter|ash|cendres brutes|rohasche']);
    v.moisture = pct([r'wilgotno[śs][ćc]|woda|moisture|humidité|feuchtigkeit|feuchte']);

    // Energia.
    final kcalKg = RegExp(r'(\d[\d .]{2,6})\s*kcal\s*/\s*kg').firstMatch(flat);
    final kcal100 = RegExp(r'(\d{2,3}(?:\.\d)?)\s*kcal\s*/?\s*(?:na\s*)?100\s*g').firstMatch(flat);
    final mj = RegExp(r'(\d{1,2}(?:\.\d{1,2})?)\s*mj\s*/\s*kg').firstMatch(flat);
    final kj100 = RegExp(r'(\d{3,4})\s*kj\s*/?\s*(?:na\s*)?100\s*g').firstMatch(flat);
    if (kcal100 != null) {
      v.kcalPer100g = double.tryParse(kcal100.group(1)!);
    } else if (kcalKg != null) {
      final x = double.tryParse(kcalKg.group(1)!.replaceAll(RegExp(r'[ .]'), ''));
      if (x != null && x > 300) v.kcalPer100g = x / 10;
    } else if (mj != null) {
      final x = double.tryParse(mj.group(1)!);
      if (x != null) v.kcalPer100g = x * 239 / 10;
    } else if (kj100 != null) {
      final x = double.tryParse(kj100.group(1)!);
      if (x != null) v.kcalPer100g = x / 4.184;
    }
    if (v.kcalPer100g != null) {
      v.kcalPer100g = double.parse(v.kcalPer100g!.toStringAsFixed(0));
      if (v.kcalPer100g! < 40 || v.kcalPer100g! > 700) v.kcalPer100g = null;
    }

    // Masa opakowania.
    final pack = RegExp(r'(?:^|[^0-9.])(\d{1,2}(?:\.\d{1,3})?)\s*kg\b(?!\s*/)').firstMatch(flat) ??
        RegExp(r'(?:^|[^0-9.])(\d{2,4})\s*g\b(?!\s*/)').firstMatch(flat);
    if (pack != null) {
      final x = double.tryParse(pack.group(1)!);
      if (x != null) v.packageGrams = pack.group(0)!.contains('kg') ? x * 1000 : x;
    }

    // Skład.
    final c = RegExp(
            r'(?:skład|sklad|składniki|composition|ingredients|zusammensetzung)\s*:\s*(.+?)(?=składniki analityczne|skladniki analityczne|analytical|analytische|constituants analytiques|dodatki|additives|zusatzstoffe|$)')
        .firstMatch(flat);
    if (c != null) {
      var s = c.group(1)!.trim();
      if (s.length > 600) s = '${s.substring(0, 600)}…';
      if (s.length > 10) v.composition = s[0].toUpperCase() + s.substring(1);
    }
    return v;
  }
}

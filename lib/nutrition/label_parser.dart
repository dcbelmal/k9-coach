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

  // Nazwy pozycji tabeli (do rozpoznania tabel czytanych kolumnami). Kolejność ma znaczenie:
  // dłuższe nazwy przed krótszymi.
  static const _kinds = {
    'protein': r'rohprotein|białk|bialk|biatk|protein|protéine|eiwei',
    'fat': r'rohfett|oils? and fats|tłuszcz|tluszcz|matières grasses|matieres grasses|fett|fat(?!ty)',
    'fiber': r'rohfaser|włókn|wlokn|fib(?:re|er)|cellulose',
    'ash': r'rohasche|substancje nieorganiczne|inorganic matter|popiół|popiol|cendres|asche|\bash',
    'moisture': r'wilgotno|\bwoda|moisture|humidit|feuchtigkeit|feuchte',
    'other': r'wap[ńn]|fosfor|s[óo]d\b|potas|magnez|omega|kwas|\bepa\b|\bdha\b|calcium|phosph|sodium|potassium|kalzium|natrium|witamin|vitamin|tauryn|taurin|l-karnityn|carnitin|glukozamin|glucosamin|chondroityn|chondroitin',
  };
  static final _names = RegExp(_kinds.values.join('|'));

  static LabelValues parse(String raw) {
    final v = LabelValues();
    // Ujednolicenie: małe litery, jedna spacja, poprawki częstych błędów OCR.
    final t = raw
        .toLowerCase()
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAllMapped(RegExp(r'(\d) ?[,.] ?(\d)'), (m) => '${m[1]}.${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)\s*(?:o/o|°/o|0/o|%o)'), (m) => '${m[1]}%')
        // OCR myli „0” z „o”/„O” w liczbach: „1O%” → „10%”.
        .replaceAllMapped(RegExp(r'(\d)[oO](?=\s*%|\d)'), (m) => '${m[1]}0');
    final flat = t.replaceAll('\n', ' ');

    // Wartości procentowe szukamy najpierw w sekcji „składniki analityczne”,
    // żeby nie pomylić ich z procentami w składzie (np. „kurczak 26%”).
    final a = RegExp(
            r'składniki analityczne|skladniki analityczne|sk.adniki analityczne|analytical constituents|analytische bestandteile|constituants analytiques|analiza')
        .firstMatch(flat);
    final section = a == null ? flat : flat.substring(a.start);

    double? pct(List<String> names) {
      for (final n in names) {
        for (final m in RegExp('(?:^|[^a-ząćęłńóśźż])(?:$n)$_gap$_num\\s*%').allMatches(section)) {
          // „białko tłuszcz włókno 25%” – liczba należy do innej pozycji (tabela czytana kolumnami).
          if (_names.allMatches(m.group(0)!).length > 1) continue;
          final x = double.tryParse(m.group(1)!);
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
    _columns(section, v);

    // Energia.
    v.kcalPer100g = _energy(flat);
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

  /// Tabela odczytana kolumnami: najpierw same nazwy, potem same liczby.
  /// Przypisuje liczby po kolei i uzupełnia tylko puste pola.
  static void _columns(String text, LabelValues v) {
    final tokens = <(int, int, String)>[]; // start, koniec, rodzaj ('%' = liczba)
    for (final e in _kinds.entries) {
      for (final m in RegExp(e.value).allMatches(text)) {
        tokens.add((m.start, m.end, e.key));
      }
    }
    for (final m in RegExp('$_num\\s*%').allMatches(text)) {
      tokens.add((m.start, m.end, '%'));
    }
    tokens.sort((a, b) => a.$1.compareTo(b.$1));
    final t = <(int, int, String)>[];
    for (final x in tokens) {
      if (t.isEmpty || x.$1 >= t.last.$2) t.add(x);
    }
    var i = 0;
    while (i < t.length) {
      if (t[i].$3 == '%') {
        i++;
        continue;
      }
      // Ciąg nazw bez liczb pomiędzy.
      var j = i;
      while (j + 1 < t.length &&
          t[j + 1].$3 != '%' &&
          !RegExp(r'\d').hasMatch(text.substring(t[j].$2, t[j + 1].$1)) &&
          t[j + 1].$1 - t[j].$2 < 40) {
        j++;
      }
      final names = t.sublist(i, j + 1);
      // Potem ciąg samych liczb z procentami.
      final values = <double>[];
      var k = j + 1;
      while (k < t.length && t[k].$3 == '%') {
        final gap = text.substring(t[k - 1].$2, t[k].$1);
        if (gap.length > 40 || (values.isNotEmpty && RegExp(r'[a-ząćęłńóśźż]{3}').hasMatch(gap))) break;
        values.add(double.parse(RegExp(_num).firstMatch(text.substring(t[k].$1, t[k].$2))!.group(1)!));
        k++;
      }
      if (names.length >= 3 && values.length >= names.length) {
        for (var n = 0; n < names.length; n++) {
          final x = values[n];
          if (x > 100) continue;
          switch (names[n].$3) {
            case 'protein':
              v.protein ??= x;
            case 'fat':
              v.fat ??= x;
            case 'fiber':
              v.fiber ??= x;
            case 'ash':
              v.ash ??= x;
            case 'moisture':
              v.moisture ??= x;
          }
        }
        return;
      }
      i = j + 1;
    }
  }

  /// Kaloryczność w kcal/100 g z różnych zapisów: „3 890 kcal/kg”, „kcal/kg: 3890”,
  /// „389 kcal/100 g”, „Energia metaboliczna 15,9 MJ/kg”, „1630 kJ/100 g”, „Energia: 3890”.
  static double? _energy(String t) {
    double? n(String s) => double.tryParse(s.replaceAll(' ', ''));
    double? per100(double? x) => x == null ? null : (x >= 1000 ? x / 10 : x);
    const num = r'(\d(?:[\d ]{0,5}\d)?(?:\.\d{1,2})?)';
    const kg = r'(?:kg|1\s*kg|1000\s*g)';
    final rules = <(String, double? Function(double))>[
      ('$num\\s*kcal\\s*(?:me\\s*|em\\s*)?(?:/|na|per|pro|par|w)?\\s*100\\s*g', (x) => x),
      ('kcal\\s*(?:me\\s*|em\\s*)?(?:/|na|per|w)\\s*100\\s*g\\)?\\s*[:=-]?\\s*$num(?!\\s*%)', (x) => x),
      ('100\\s*g\\)?\\s*[:=-]?\\s*$num\\s*kcal', (x) => x),
      ('$num\\s*kcal\\s*(?:me\\s*|em\\s*)?(?:/|na|per|pro|par)\\s*$kg', (x) => x / 10),
      ('kcal\\s*(?:me\\s*|em\\s*)?(?:/|na|per)\\s*$kg\\)?\\s*[:=-]?\\s*$num(?!\\s*%)', (x) => x / 10),
      ('$num\\s*mj\\s*(?:me\\s*)?(?:/|na|per)\\s*$kg', (x) => x * 23.9),
      ('mj\\s*(?:/|na|per)\\s*$kg\\)?\\s*[:=-]?\\s*$num', (x) => x * 23.9),
      ('$num\\s*kj\\s*(?:/|na|per|w)?\\s*100\\s*g', (x) => x / 4.184),
      ('$num\\s*kj\\s*(?:/|na|per)\\s*$kg', (x) => x / 41.84),
      // „Energia metaboliczna … 3890 kcal” / „Energy: 389” – bez jednostki na kg/100 g.
      ('(?:energia metaboliczna|warto[śs][ćc] energetyczna|energia|metaboli[sz]able energy|energy|umsetzbare energie|energie|énergie)'
          '[^0-9%]{0,40}?$num\\s*(kcal|kj|mj)?(?!\\s*(?:%|g\\b|kg\\b|[\\d.]))', (x) => x),
      ('(?:^|[^\\d.])(\\d \\d{3}|\\d{4})\\s*kcal\\b', (x) => x / 10),
    ];
    for (var i = 0; i < rules.length; i++) {
      for (final m in RegExp(rules[i].$1).allMatches(t)) {
        final x = n(m.group(1)!);
        if (x == null) continue;
        double? r;
        if (i == rules.length - 2) {
          final unit = m.groupCount >= 2 ? m.group(2) : null;
          r = switch (unit) {
            'mj' => x * 23.9,
            'kj' => x >= 3000 ? x / 41.84 : x / 4.184,
            _ => per100(x),
          };
        } else {
          r = rules[i].$2(x);
        }
        if (r != null && r >= 40 && r <= 700) return r;
      }
    }
    return null;
  }
}

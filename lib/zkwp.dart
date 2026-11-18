import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'models_ext.dart';
import 'l10n/l10n.dart';

/// Wystawa z terminarza ZKwP (https://zkwp.pl/wystawy.php).
class ZkwpShow {
  final DateTime date;
  final DateTime? endDate;
  final String place; // np. "GDAŃSK (O/Gdynia)"
  final String description; // np. "międzynarodowa - CACIB · DUO CACIB"
  /// Kod kraju ISO (PL = terminarz ZKwP, inne = kalendarz FCI).
  final String country;
  /// true = wystawa z kalendarza FCI (tylko miasto i data, zawsze CACIB).
  final bool fromFci;

  ZkwpShow({
    required this.date,
    this.endDate,
    required this.place,
    required this.description,
    this.country = 'PL',
    this.fromFci = false,
  });

  String get city {
    final i = place.indexOf('(');
    final c = (i > 0 ? place.substring(0, i) : place).trim();
    return c.split(RegExp(r'[\s-]+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  String get _d => description.toLowerCase();

  ShowType get type {
    if (_d.contains('międzynarodow') || _d.contains('cacib')) return ShowType.international;
    if (_d.contains('klubow')) return ShowType.club;
    if (_d.contains('specjalistyczn')) return ShowType.specialty;
    return ShowType.national;
  }

  String get title {
    final kind = switch (type) {
      ShowType.international => tr('Międzynarodowa wystawa psów'),
      ShowType.national => tr('Krajowa wystawa psów'),
      ShowType.club => tr('Wystawa klubowa'),
      ShowType.specialty => tr('Wystawa specjalistyczna'),
    };
    return '$kind – $city';
  }

  /// Grupy FCI, których dotyczy wystawa. Pusty zbiór = wszystkie rasy, null = nie wiadomo.
  Set<int>? get groups {
    final d = _d;
    // Numer grupy podany wprost ("IV grupy FCI", "9 Grupa FCI").
    final m = RegExp(r'\b(x|ix|viii|vii|vi|v|iv|iii|ii|i|10|[1-9])\s*\.?\s*gr', caseSensitive: false).firstMatch(d) ??
        RegExp(r'grup[ay]?\s*(?:fci\s*)?(x|ix|viii|vii|vi|v|iv|iii|ii|i|10|[1-9])\b', caseSensitive: false).firstMatch(d);
    if (m != null) {
      final v = m.group(1)!.toUpperCase();
      final n = int.tryParse(v) ?? (romanNumerals.indexOf(v) + 1);
      if (n >= 1 && n <= 10) return {n};
    }
    if (d.contains('myśliwsk')) return {3, 4, 5, 6, 7, 8};
    if (type == ShowType.international || type == ShowType.national) {
      if (d.contains('klubow') || d.contains('specjalistyczn')) return null;
      // Np. "krajowa polskich owczarków podhalańskich" – wystawa tylko dla jednej rasy.
      final rest = d
          .replaceAll(RegExp(r'krajow\w*|międzynarodow\w*|cacib|duo|wystaw\w*|ps(ów|y) rasow\w*|zwycięzca polski|champion of champions show|\(poranna\)|\(popołudniowa\)|\d+|[-–·,()]'), ' ')
          .trim();
      if (rest.length > 3) return _breedGroup(rest) == null ? null : {_breedGroup(rest)!};
      return {}; // wszystkie rasy
    }
    // Klubowe i specjalistyczne: rozpoznanie po nazwie rasy.
    final g = _breedGroup(d);
    return g == null ? null : {g};
  }

  static int? _breedGroup(String d) {
    if (d.contains('buldogów francuskich') || d.contains('buldog francuski')) return 9;
    if (d.contains('buldogów angielskich')) return 2;
    if (d.contains('owczark') || d.contains('pasterski') || d.contains('collie')) return 1;
    if (d.contains('pinczer') || d.contains('sznaucer') || d.contains('molos') || d.contains('rottweil') ||
        d.contains('dobermann') || d.contains('bokser') || d.contains('mastif') || d.contains('nowofundland')) {
      return 2;
    }
    if (d.contains('terier')) return 3;
    if (d.contains('jamnik')) return 4;
    if (d.contains('szpic') || d.contains('nordyck') || d.contains('husky') || d.contains('akit') || d.contains('pierwotn')) return 5;
    if (d.contains('gończ') || d.contains('posokow') || d.contains('beagl')) return 6;
    if (d.contains('wyżł') || d.contains('seter')) return 7;
    if (d.contains('retriever') || d.contains('spaniel') || d.contains('aporter') || d.contains('płochacz')) return 8;
    if (d.contains('toy') || d.contains('ozdobn') || d.contains('pudl') || d.contains('chihuahua')) return 9;
    if (d.contains('chart')) return 10;
    return guessFciGroup(d);
  }

  /// Czy wystawa jest dla psa z daną grupą FCI.
  bool matches(int? fciGroup) {
    final g = groups;
    if (g == null) return false;
    if (g.isEmpty) return true;
    return fciGroup != null && g.contains(fciGroup);
  }

  String get groupsLabel {
    final g = groups;
    if (g == null) return tr('rasy: sprawdź u organizatora');
    if (g.isEmpty) return tr('wszystkie rasy');
    return tr('gr. {0}', [g.map((e) => romanNumerals[e - 1]).join(', ')]);
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'end': endDate?.toIso8601String(),
        'place': place,
        'desc': description,
        if (country != 'PL') 'c': country,
        if (fromFci) 'fci': true,
      };

  factory ZkwpShow.fromJson(Map<String, dynamic> j) => ZkwpShow(
        date: DateTime.parse(j['date']),
        endDate: j['end'] == null ? null : DateTime.parse(j['end']),
        place: j['place'],
        description: j['desc'],
        country: j['c'] ?? 'PL',
        fromFci: j['fci'] == true,
      );
}

const _months = {
  'styczeń': 1, 'styczen': 1, 'luty': 2, 'marzec': 3, 'kwiecień': 4, 'kwiecien': 4, 'maj': 5, 'czerwiec': 6,
  'lipiec': 7, 'sierpień': 8, 'sierpien': 8, 'wrzesień': 9, 'wrzesien': 9, 'październik': 10, 'pazdziernik': 10,
  'listopad': 11, 'grudzień': 12, 'grudzien': 12,
};

/// ISO-8859-2 → tekst (na wypadek starszego kodowania strony).
String _latin2(List<int> bytes) {
  const hi = {
    0xA1: 'Ą', 0xA3: 'Ł', 0xA6: 'Ś', 0xAC: 'Ź', 0xAF: 'Ż', 0xB1: 'ą', 0xB3: 'ł', 0xB6: 'ś', 0xBC: 'ź', 0xBF: 'ż',
    0xC6: 'Ć', 0xCA: 'Ę', 0xD1: 'Ń', 0xD3: 'Ó', 0xE6: 'ć', 0xEA: 'ę', 0xF1: 'ń', 0xF3: 'ó',
  };
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b < 0x80 ? String.fromCharCode(b) : (hi[b] ?? String.fromCharCode(b)));
  }
  return sb.toString();
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return _latin2(bytes);
  }
}

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));

/// Zamienia HTML terminarza na listę wystaw.
List<ZkwpShow> parseZkwp(String html, int year) {
  var t = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>|</(p|li|div|tr|h\d|ul|ol|dt|dd)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = _unescape(t);
  final lines = [
    for (final l in t.split('\n'))
      if (l.replaceAll(RegExp(r'\s+'), ' ').trim().isNotEmpty) l.replaceAll(RegExp(r'\s+'), ' ').trim()
  ];

  final start = lines.indexWhere((l) => l.toLowerCase().contains('terminarz wystaw'));
  final out = <ZkwpShow>[];
  int? month;
  DateTime? date, end;
  String? place;
  final desc = <String>[];
  final entry = RegExp(r'^(\d{1,2})(?:\s*[-–]\s*(\d{1,2}))?\.?\s+(.{2,})$');
  final dayOnly = RegExp(r'^(\d{1,2})(?:\s*[-–]\s*(\d{1,2}))?\.?$');

  void flush() {
    if (date != null && place != null) {
      out.add(ZkwpShow(date: date!, endDate: end, place: place!, description: desc.join(' · ')));
    }
    date = null;
    end = null;
    place = null;
    desc.clear();
  }

  (DateTime, DateTime?) mkDate(int m, String d1, String? d2) {
    final a = int.parse(d1);
    final s = DateTime(year, m, a);
    if (d2 == null) return (s, null);
    final b = int.parse(d2);
    // Przełom miesiąca, np. "31-01".
    final e = b < a ? DateTime(year, m + 1, b) : DateTime(year, m, b);
    return (s, e);
  }

  for (var i = start < 0 ? 0 : start + 1; i < lines.length; i++) {
    final l = lines[i];
    final low = l.toLowerCase();
    final mm = _months[low.replaceAll(RegExp(r'[^a-ząćęłńóśźż]'), '')];
    if (mm != null && l.length < 20) {
      flush();
      month = mm;
      continue;
    }
    if (month == null) continue;
    if (low.startsWith('terminarz') || low.contains('copyright') || low.contains('©')) {
      flush();
      if (low.contains('copyright') || low.contains('©')) break;
      continue;
    }
    var e = entry.firstMatch(l);
    if (e == null) {
      final d = dayOnly.firstMatch(l);
      if (d != null && i + 1 < lines.length) {
        e = entry.firstMatch('${l.trim()} ${lines[i + 1]}');
        if (e != null) i++;
      }
    }
    if (e != null) {
      flush();
      final (s, en) = mkDate(month, e.group(1)!, e.group(2));
      date = s;
      end = en;
      place = e.group(3)!.trim();
      continue;
    }
    if (place != null) desc.add(l);
  }
  flush();
  return out;
}

class ZkwpService {
  static const _cacheKey = 'zkwp_cache_';

  static Uri url(int year) => Uri.parse('https://zkwp.pl/wystawy.php?l=&rok=$year');

  /// Pobiera terminarz (z internetu, a gdy się nie uda – z pamięci telefonu).
  static Future<(List<ZkwpShow>, DateTime?, String?)> load(int year, {bool refresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    List<ZkwpShow>? cached;
    DateTime? cachedAt;
    final raw = prefs.getString('$_cacheKey$year');
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      cached = [for (final e in j['shows'] as List) ZkwpShow.fromJson(e)];
      cachedAt = DateTime.parse(j['at']);
    }
    final fresh = cachedAt != null && DateTime.now().difference(cachedAt).inHours < 12;
    if (cached != null && fresh && !refresh) return (cached, cachedAt, null);
    try {
      final r = await http.get(url(year), headers: {'User-Agent': 'Mozilla/5.0 (Valkor Coach)'}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final shows = parseZkwp(_decode(r.bodyBytes), year);
      if (shows.isEmpty && cached != null) return (cached, cachedAt, tr('Nie udało się odczytać terminarza.'));
      final now = DateTime.now();
      await prefs.setString(
          '$_cacheKey$year', jsonEncode({'at': now.toIso8601String(), 'shows': shows.map((e) => e.toJson()).toList()}));
      return (shows, now, null);
    } catch (e) {
      return (cached ?? <ZkwpShow>[], cachedAt, tr('Brak połączenia ze stroną ZKwP.'));
    }
  }
}

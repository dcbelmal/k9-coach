import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../zkwp.dart';
import '../l10n/l10n.dart';

/// Opis wystawy z kalendarza FCI – FCI publikuje tylko wystawy międzynarodowe (CACIB).
const fciShowDescription = 'międzynarodowa - CACIB';

/// Odczytuje datę "M/D/RRRR" (czasem FCI podaje "DD/MM/RRRR").
/// Zwraca (początek, koniec) albo null, gdy nie da się odczytać.
(DateTime, DateTime?)? parseFciDates(String raw) {
  final parts = raw.split(RegExp(r'\s*[-–]\s*')).where((e) => e.trim().isNotEmpty).toList();
  final toks = <List<int>>[];
  final padded = <bool>[];
  for (final p in parts) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(p.trim());
    if (m == null) return null;
    toks.add([int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)]);
    padded.add(m.group(1)!.length == 2 && m.group(1)!.startsWith('0'));
  }
  if (toks.isEmpty) return null;

  List<DateTime>? attempt(bool monthFirst) {
    final out = <DateTime>[];
    for (final t in toks) {
      final mo = monthFirst ? t[0] : t[1];
      final d = monthFirst ? t[1] : t[0];
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      final dt = DateTime(t[2], mo, d);
      if (dt.month != mo) return null; // np. 31 kwietnia
      out.add(dt);
    }
    final span = out.last.difference(out.first).inDays;
    if (span < 0 || span > 7) return null;
    return out;
  }

  // Zapis z zerem na początku ("01/08/2025") to zwykle format europejski.
  final preferDayFirst = padded.every((e) => e);
  final r = preferDayFirst ? (attempt(false) ?? attempt(true)) : (attempt(true) ?? attempt(false));
  if (r == null) return null;
  return (r.first, r.length > 1 ? r.last : null);
}

/// Zamienia stronę https://www.fci.be/en/schedules/concours.aspx?iso=XX na listę wystaw.
List<ZkwpShow> parseFci(String html, String country) {
  final rx = RegExp(r'VilleLabel_\d+"[^>]*>([^<]*)<[\s\S]*?DateLabel_\d+"[^>]*>([^<]*)<');
  final seen = <String>{};
  final out = <ZkwpShow>[];
  for (final m in rx.allMatches(html)) {
    final city = _clean(m.group(1)!);
    final dates = parseFciDates(_clean(m.group(2)!));
    if (city.isEmpty || dates == null) continue;
    final (start, end) = dates;
    final key = '$city|$start|$end';
    if (!seen.add(key)) continue; // FCI czasem powtarza ten sam wiersz
    out.add(ZkwpShow(
      date: start,
      endDate: end,
      place: city,
      description: fciShowDescription,
      country: country,
      fromFci: true,
    ));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

String _clean(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class FciService {
  static const _cacheKey = 'fci_cache_';

  static Uri url(String country) => Uri.parse('https://www.fci.be/en/schedules/concours.aspx?iso=$country');

  /// Wystawy CACIB w danym kraju (z internetu, a gdy się nie uda – z pamięci telefonu).
  /// Zwraca (wystawy, kiedy pobrano, błąd).
  static Future<(List<ZkwpShow>, DateTime?, String?)> load(String country, {bool refresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    List<ZkwpShow>? cached;
    DateTime? cachedAt;
    final raw = prefs.getString('$_cacheKey$country');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        cached = [for (final e in j['shows'] as List) ZkwpShow.fromJson(e)];
        cachedAt = DateTime.parse(j['at']);
      } catch (_) {}
    }
    final fresh = cachedAt != null && DateTime.now().difference(cachedAt).inHours < 24;
    if (cached != null && fresh && !refresh) return (cached, cachedAt, null);
    try {
      final r = await http
          .get(url(country), headers: {'User-Agent': 'Mozilla/5.0 (Valkor Coach)'})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final shows = parseFci(utf8.decode(r.bodyBytes, allowMalformed: true), country);
      final now = DateTime.now();
      await prefs.setString(
          '$_cacheKey$country', jsonEncode({'at': now.toIso8601String(), 'shows': shows.map((e) => e.toJson()).toList()}));
      return (shows, now, null);
    } catch (_) {
      return (cached ?? <ZkwpShow>[], cachedAt, tr('Brak połączenia ze stroną FCI.'));
    }
  }
}

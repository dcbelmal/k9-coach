import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'label_parser.dart';

/// Dane odczytane ze strony producenta (albo z wklejonego tekstu).
class WebImportResult {
  final String name, brand;
  final LabelValues values;
  final Uint8List? image;
  final bool fetched; // false = strona nie odpowiedziała
  const WebImportResult({this.name = '', this.brand = '', required this.values, this.image, this.fetched = true});
}

/// Pobiera stronę produktu i wyciąga z niej wartości odżywcze tym samym
/// parserem co dla zdjęcia etykiety. Działa z większością sklepów i stron producentów,
/// które pokazują skład i analizę w treści strony.
class WebImport {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'pl,en;q=0.8',
  };

  /// Pierwszy adres http(s) w tekście albo null.
  static Uri? findUrl(String s) {
    final m = RegExp(r'''https?://[^\s<>"']+''').firstMatch(s.trim()) ??
        RegExp(r'''^(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:/[^\s<>"']*)?$''', caseSensitive: false)
            .firstMatch(s.trim());
    if (m == null) return null;
    var u = m.group(0)!;
    if (!u.startsWith('http')) u = 'https://$u';
    return Uri.tryParse(u);
  }

  /// Link → pobranie strony; zwykły tekst → odczyt jak z etykiety.
  static Future<WebImportResult> fromInput(String input, {http.Client? client}) async {
    final url = findUrl(input);
    if (url == null) return WebImportResult(values: LabelParser.parse(input));
    final cl = client ?? http.Client();
    try {
      final r = await cl.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return WebImportResult(values: LabelValues(), fetched: false);
      final res = parseHtml(utf8.decode(r.bodyBytes, allowMalformed: true));
      Uint8List? img;
      final imgUrl = _meta(utf8.decode(r.bodyBytes, allowMalformed: true), 'og:image');
      if (imgUrl.isNotEmpty) {
        try {
          final ir = await cl.get(url.resolve(imgUrl), headers: _headers).timeout(const Duration(seconds: 10));
          final type = ir.headers['content-type'] ?? '';
          if (ir.statusCode == 200 && type.startsWith('image/') && ir.bodyBytes.length < 5000000) img = ir.bodyBytes;
        } catch (_) {}
      }
      return WebImportResult(name: res.name, brand: res.brand, values: res.values, image: img);
    } catch (e) {
      debugPrint('Strona produktu: $e');
      return WebImportResult(values: LabelValues(), fetched: false);
    } finally {
      if (client == null) cl.close();
    }
  }

  /// HTML → nazwa, marka i wartości. Publiczne, żeby dało się testować.
  static WebImportResult parseHtml(String html) {
    final name = _clean(_meta(html, 'og:title').isNotEmpty
        ? _meta(html, 'og:title')
        : (_tag(html, 'h1').isNotEmpty ? _tag(html, 'h1') : _tag(html, 'title')));
    final brand = _clean(_meta(html, 'og:site_name'));
    var text = htmlToText(html);
    // Dane produktu w JSON-LD (np. opis) też bywają przydatne.
    for (final m in RegExp(r'<script[^>]+ld\+json[^>]*>([\s\S]*?)</script>', caseSensitive: false).allMatches(html)) {
      text += '\n${_decode(m.group(1)!.replaceAll(RegExp(r'\\[nrt]'), ' '))}';
    }
    return WebImportResult(name: name, brand: brand, values: LabelParser.parse(text));
  }

  /// Usuwa znaczniki, skrypty i style; zostawia tekst w rozsądnych liniach.
  static String htmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<(script|style|noscript|svg|head)\b[\s\S]*?</\1>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|li|tr|h[1-6]|section|article|ul|ol|table|dd|dt)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decode(s);
    return s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  static String _meta(String html, String prop) {
    final p = RegExp.escape(prop);
    final m = RegExp('<meta[^>]+(?:property|name)=["\']$p["\'][^>]*content=["\']([^"\']*)["\']', caseSensitive: false)
            .firstMatch(html) ??
        RegExp('<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$p["\']', caseSensitive: false)
            .firstMatch(html);
    return m == null ? '' : _decode(m.group(1)!).trim();
  }

  static String _tag(String html, String tag) {
    final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false).firstMatch(html);
    return m == null ? '' : _decode(m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ' ')).trim();
  }

  static String _clean(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // „Nazwa | Sklep” → „Nazwa”
    t = t.split(RegExp(r'\s[|–—]\s|\s-\s')).first.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  static const _entities = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'percnt': '%', 'deg': '°',
    'oacute': 'ó', 'Oacute': 'Ó', 'eacute': 'é', 'egrave': 'è', 'agrave': 'à', 'auml': 'ä', 'ouml': 'ö',
    'uuml': 'ü', 'szlig': 'ß', 'ndash': '–', 'mdash': '—', 'rsquo': '’', 'lsquo': '‘', 'bdquo': '„',
    'rdquo': '”', 'ldquo': '“', 'hellip': '…', 'middot': '·', 'times': '×',
  };

  static String _decode(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
        final e = m.group(1)!;
        if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
        if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
        return _entities[e] ?? m.group(0)!;
      });
}

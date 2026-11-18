import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage/safe_prefs.dart';
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

  /// Limity pobierania: strona i obraz są czytane strumieniowo i przerywane
  /// po przekroczeniu limitu – także gdy serwer nie podaje Content-Length.
  static const maxPageBytes = 3 * 1024 * 1024;
  static const maxImageBytes = 3 * 1024 * 1024;
  static const maxImageSide = 4096;
  static const minImageSide = 16;

  /// Sprawdzenie, czy obraz da się zdekodować (w aplikacji – dekoder Fluttera).
  static Future<bool> Function(Uint8List bytes) canDecode = _canDecode;

  static Future<bool> _canDecode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pobiera odpowiedź, ale najwyżej [maxBytes] bajtów. Zwraca null, gdy limit
  /// przekroczono, status nie jest 200 albo typ treści się nie zgadza.
  static Future<(Uint8List, String)?> fetchLimited(http.Client cl, Uri url, int maxBytes,
      {Duration timeout = const Duration(seconds: 15), bool Function(String type)? acceptType}) async {
    final req = http.Request('GET', url)..headers.addAll(_headers);
    final res = await cl.send(req).timeout(timeout);
    final type = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || (acceptType != null && !acceptType(type))) {
      unawaited(res.stream.listen(null).cancel());
      return null;
    }
    final declared = res.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(res.stream.listen(null).cancel());
      return null;
    }
    final buf = BytesBuilder(copy: false);
    final done = Completer<bool>();
    late StreamSubscription<List<int>> sub;
    sub = res.stream.listen((chunk) {
      buf.add(chunk);
      if (buf.length > maxBytes) {
        sub.cancel();
        if (!done.isCompleted) done.complete(false);
      }
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    }, onDone: () {
      if (!done.isCompleted) done.complete(true);
    }, cancelOnError: true);
    final ok = await done.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      return false;
    });
    return ok ? (buf.takeBytes(), type) : null;
  }

  /// Format i wymiary obrazu z nagłówka (PNG, JPEG, GIF, WebP) albo null.
  static (String, int, int)? imageInfo(Uint8List b) {
    if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      final d = ByteData.sublistView(b);
      return ('png', d.getUint32(16), d.getUint32(20));
    }
    if (b.length >= 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return ('gif', b[6] | (b[7] << 8), b[8] | (b[9] << 8));
    }
    if (b.length >= 30 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) {
      final kind = String.fromCharCodes(b.sublist(12, 16));
      if (kind == 'VP8X') return ('webp', 1 + (b[24] | b[25] << 8 | b[26] << 16), 1 + (b[27] | b[28] << 8 | b[29] << 16));
      if (kind == 'VP8 ' && b.length >= 30) return ('webp', (b[26] | b[27] << 8) & 0x3fff, (b[28] | b[29] << 8) & 0x3fff);
      if (kind == 'VP8L' && b.length >= 25) {
        final v = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
        return ('webp', (v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1);
      }
      return null;
    }
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) return null;
        final m = b[i + 1];
        final len = (b[i + 2] << 8) | b[i + 3];
        if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
          return ('jpeg', (b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
        }
        i += 2 + len;
      }
    }
    return null;
  }

  /// Obraz przyjmujemy tylko, gdy ma znany format, rozsądne wymiary i da się go zdekodować.
  static Future<bool> validImage(Uint8List bytes) async {
    final info = imageInfo(bytes);
    if (info == null) return false;
    final (_, w, h) = info;
    if (w < minImageSide || h < minImageSide || w > maxImageSide || h > maxImageSide) return false;
    return canDecode(bytes);
  }

  /// Link → pobranie strony; zwykły tekst → odczyt jak z etykiety.
  static Future<WebImportResult> fromInput(String input, {http.Client? client}) async {
    final url = findUrl(input);
    if (url == null) return WebImportResult(values: LabelParser.parse(input));
    final cl = client ?? http.Client();
    try {
      final page = await fetchLimited(cl, url, maxPageBytes);
      if (page == null) return WebImportResult(values: LabelValues(), fetched: false);
      final html = utf8.decode(page.$1, allowMalformed: true);
      final res = parseHtml(html);
      Uint8List? img;
      final imgUrl = _meta(html, 'og:image');
      if (imgUrl.isNotEmpty) {
        try {
          final target = url.resolve(imgUrl);
          if (target.scheme == 'https' || target.scheme == 'http') {
            final r = await fetchLimited(cl, target, maxImageBytes,
                timeout: const Duration(seconds: 10),
                acceptType: (t) => RegExp(r'^image/(jpeg|png|webp|gif)').hasMatch(t.toLowerCase()));
            if (r != null && await validImage(r.$1)) img = r.$1;
          }
        } catch (_) {}
      }
      return WebImportResult(name: res.name, brand: res.brand, values: res.values, image: img);
    } catch (e) {
      logError('Strona produktu', e);
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

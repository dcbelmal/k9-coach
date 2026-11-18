import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart' show newId;
import 'catalog.dart';
import 'nutrition_models.dart';
import '../l10n/l10n.dart';

/// Wyszukiwanie produktu po kodzie kreskowym w otwartych bazach
/// Open Pet Food Facts / Open Food Facts (bez klucza i opłat).
/// Gdy brak internetu albo produktu – zwraca null i użytkownik uzupełnia dane ręcznie.
/// Wynik wyszukiwania po kodzie.
class LookupResult {
  final FoodProduct? product;
  final bool offline; // żadne źródło nie odpowiedziało (brak internetu)
  final List<String> checked; // nazwy sprawdzonych baz
  const LookupResult(this.product, this.offline, this.checked);
}

class ProductLookup {
  static const _off = [
    ('world.openpetfoodfacts.org', 'Open Pet Food Facts', 'openpetfoodfacts'),
    ('world.openfoodfacts.org', 'Open Food Facts', 'openfoodfacts'),
    ('world.openproductsfacts.org', 'Open Products Facts', 'openproductsfacts'),
  ];
  static const _fields =
      'product_name,product_name_pl,product_name_en,generic_name,brands,quantity,product_quantity,ingredients_text,ingredients_text_pl,ingredients_text_en,nutriments,categories_tags';
  static const _ua = {'User-Agent': 'ValkorCoach/0.6 (Android; dog nutrition app)'};

  static Future<FoodProduct?> byBarcode(String code, {http.Client? client}) async =>
      (await lookup(code, client: client)).product;

  /// Szuka kolejno w bazach Open Food Facts (karmy, żywność, produkty),
  /// a gdy tam nic nie ma – w katalogu UPCitemdb (tylko nazwa i producent).
  static Future<LookupResult> lookup(String code, {http.Client? client}) async {
    final c = code.trim();
    if (!RegExp(r'^\d{6,14}$').hasMatch(c)) return const LookupResult(null, false, []);
    final known = FoodCatalog.byBarcode(c);
    if (known != null) return LookupResult(known, false, [tr('Katalog Valkor')]);
    final cl = client ?? http.Client();
    final checked = <String>[];
    var answered = 0;
    try {
      for (final (host, name, source) in _off) {
        checked.add(name);
        try {
          final r = await cl
              .get(Uri.https(host, '/api/v2/product/$c.json', {'fields': _fields}), headers: _ua)
              .timeout(const Duration(seconds: 8));
          answered++;
          if (r.statusCode != 200) continue;
          final p = parse(c, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>, source: source);
          if (p != null) return LookupResult(p, false, checked);
        } catch (e) {
          debugPrint('Wyszukiwanie $host: $e');
        }
      }
      checked.add(tr('UPCitemdb'));
      try {
        final r = await cl
            .get(Uri.https('api.upcitemdb.com', '/prod/trial/lookup', {'upc': c}), headers: _ua)
            .timeout(const Duration(seconds: 8));
        answered++;
        if (r.statusCode == 200) {
          final p = parseUpc(c, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
          if (p != null) return LookupResult(p, false, checked);
        }
      } catch (e) {
        debugPrint('UPCitemdb: $e');
      }
      return LookupResult(null, answered == 0, checked);
    } finally {
      if (client == null) cl.close();
    }
  }

  /// Odpowiedź UPCitemdb: zwykle tylko nazwa, marka i opis.
  static FoodProduct? parseUpc(String code, Map<String, dynamic> j) {
    final items = j['items'];
    if (items is! List || items.isEmpty) return null;
    final it = (items.first as Map).cast<String, dynamic>();
    final title = (it['title'] as String? ?? '').trim();
    if (title.isEmpty) return null;
    final brand = (it['brand'] as String? ?? '').trim();
    final text = '${it['category'] ?? ''} $title ${it['description'] ?? ''}'.toLowerCase();
    return FoodProduct(
      id: newId(),
      name: brand.isNotEmpty && title.toLowerCase().startsWith(brand.toLowerCase())
          ? title.substring(brand.length).trim()
          : title,
      brand: brand,
      type: guessType(text),
      barcode: code,
      packageGrams: parseQuantity('${it['size'] ?? ''} $title'),
      source: 'upcitemdb',
    );
  }

  /// Zamienia odpowiedź API na produkt. Publiczne, żeby dało się testować.
  static FoodProduct? parse(String code, Map<String, dynamic> j, {String source = 'openpetfoodfacts'}) {
    if (j['status'] != 1 || j['product'] is! Map) return null;
    final p = (j['product'] as Map).cast<String, dynamic>();
    final n = ((p['nutriments'] as Map?) ?? {}).cast<String, dynamic>();
    double? val(String k) {
      final v = n[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (p[k] as String?)?.trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final name = pick(['product_name_pl', 'product_name', 'product_name_en', 'generic_name']);
    final brand = ((p['brands'] as String?) ?? '').split(',').first.trim();
    var kcal = val('energy-kcal_100g');
    final kj = val('energy-kj_100g') ?? val('energy_100g');
    if (kcal == null && kj != null) kcal = kj / 4.184;
    final cats = ((p['categories_tags'] as List?) ?? []).join(' ').toLowerCase();
    final text = '$cats ${name.toLowerCase()}';
    final type = guessType(text);
    final qty = (p['product_quantity'] is num)
        ? (p['product_quantity'] as num).toDouble()
        : parseQuantity((p['quantity'] as String?) ?? '');
    final ingr = pick(['ingredients_text_pl', 'ingredients_text', 'ingredients_text_en']);
    if (name.isEmpty && brand.isEmpty) return null;
    return FoodProduct(
      id: newId(),
      name: name.isEmpty ? tr('Produkt {0}', [code]) : name,
      brand: brand,
      type: type,
      barcode: code,
      kcalPer100g: kcal == null ? null : double.parse(kcal.toStringAsFixed(0)),
      proteinPct: val('proteins_100g'),
      fatPct: val('fat_100g'),
      fiberPct: val('fiber_100g'),
      ashPct: val('ash_100g'),
      moisturePct: val('moisture_100g'),
      packageGrams: qty,
      composition: ingr.trim(),
      source: source,
    );
  }

  static ProductType guessType(String t) {
    if (RegExp(r'treat|snack|przysmak|gryzak|kość|kosc|chew|biscuit|ciastk|reward|nagrod').hasMatch(t)) {
      return ProductType.treat;
    }
    if (RegExp(r'supplement|suplement|vitamin|witamin|tablet|kapsuł|oil|olej').hasMatch(t)) {
      return ProductType.supplement;
    }
    if (RegExp(r'wet|mokr|puszk|can|saszet|pouch|pate|pasztet|tray|tacka').hasMatch(t)) return ProductType.wet;
    return ProductType.dry;
  }

  /// "12 kg", "400 g", "2 x 400g", "1,5kg" -> gramy.
  static double? parseQuantity(String q) {
    final s = q.toLowerCase().replaceAll(',', '.');
    final m = RegExp(r'(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g)\b').firstMatch(s);
    if (m == null) return null;
    final count = m.group(1) == null ? 1 : int.parse(m.group(1)!);
    final v = double.parse(m.group(2)!);
    return count * (m.group(3) == 'kg' ? v * 1000 : v);
  }
}

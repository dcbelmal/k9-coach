import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart' show newId;
import 'nutrition_models.dart';

/// Wyszukiwanie produktu po kodzie kreskowym w otwartych bazach
/// Open Pet Food Facts / Open Food Facts (bez klucza i opłat).
/// Gdy brak internetu albo produktu – zwraca null i użytkownik uzupełnia dane ręcznie.
class ProductLookup {
  static const _hosts = ['world.openpetfoodfacts.org', 'world.openfoodfacts.org'];
  static const _fields =
      'product_name,product_name_pl,brands,quantity,product_quantity,ingredients_text,ingredients_text_pl,nutriments,categories_tags';

  static Future<FoodProduct?> byBarcode(String code, {http.Client? client}) async {
    final c = code.trim();
    if (!RegExp(r'^\d{6,14}$').hasMatch(c)) return null;
    final cl = client ?? http.Client();
    try {
      for (final host in _hosts) {
        try {
          final r = await cl
              .get(Uri.https(host, '/api/v2/product/$c.json', {'fields': _fields}),
                  headers: {'User-Agent': 'ValkorCoach/0.5 (Android; dog nutrition app)'})
              .timeout(const Duration(seconds: 8));
          if (r.statusCode != 200) continue;
          final p = parse(c, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
              source: host.contains('petfood') ? 'openpetfoodfacts' : 'openfoodfacts');
          if (p != null) return p;
        } catch (e) {
          debugPrint('Wyszukiwanie $host: $e');
        }
      }
      return null;
    } finally {
      if (client == null) cl.close();
    }
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

    final name = (p['product_name_pl'] as String?)?.trim().isNotEmpty == true
        ? p['product_name_pl'] as String
        : (p['product_name'] as String? ?? '').trim();
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
    final ingr = (p['ingredients_text_pl'] as String?)?.trim().isNotEmpty == true
        ? p['ingredients_text_pl'] as String
        : (p['ingredients_text'] as String? ?? '');
    if (name.isEmpty && brand.isEmpty) return null;
    return FoodProduct(
      id: newId(),
      name: name.isEmpty ? 'Produkt $code' : name,
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

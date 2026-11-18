import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Postępy w przewodnikach treningowych (0 = nie zaczęte, 1 = w trakcie, 2 = opanowane).
class GuideStore extends ChangeNotifier {
  GuideStore._();
  static final GuideStore instance = GuideStore._();

  static const _key = 'valkor_guides_v1';
  SharedPreferences? _prefs;

  final Map<String, int> progress = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      progress
        ..clear()
        ..addAll({for (final e in j.entries) if (e.value is int) e.key: e.value as int});
    } catch (e) {
      debugPrint('Przewodniki: błąd odczytu $e');
    }
  }

  int statusOf(String id) => progress[id] ?? 0;

  Future<void> setStatus(String id, int s) async {
    if (s == 0) {
      progress.remove(id);
    } else {
      progress[id] = s;
    }
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(progress));
  }

  Future<void> reset() async {
    progress.clear();
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_key);
  }
}

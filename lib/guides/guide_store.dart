import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';
import '../storage/dog_doc_guard.dart';

/// Postępy w przewodnikach treningowych (0 = nie zaczęte, 1 = w trakcie, 2 = opanowane).
class GuideStore extends ChangeNotifier {
  GuideStore._();
  static final GuideStore instance = GuideStore._();

  static const _key = 'valkor_guides_v1';
  SharedPreferences? _prefs;

  final Map<String, int> progress = {};

  final guard = DogDocGuard(_key, 'Przewodniki');

  static Map<String, int> _parse(String? raw) {
    if (raw == null) return {};
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in j.entries) e.key: e.value as int};
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    var x = <String, int>{};
    await guard.load(_prefs!, DogProfiles.instance.activeId, (raw) => x = _parse(raw));
    progress
      ..clear()
      ..addAll(x);
    notifyListeners();
  }

  int statusOf(String id) => progress[id] ?? 0;

  Future<void> setStatus(String id, int s) async {
    if (s == 0) {
      progress.remove(id);
    } else {
      progress[id] = s;
    }
    _prefs ??= await SharedPreferences.getInstance();
    try {
      await guard.write(_prefs!, () => jsonEncode(progress), (last) {
        progress
          ..clear()
          ..addAll(_parse(last));
      });
    } finally {
      notifyListeners();
    }
  }
}

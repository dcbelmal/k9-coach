import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../files/file_store.dart';
import '../models.dart';

class GalleryPhoto {
  final String id;
  final String ref; // plik w FileStore
  DateTime date;
  String caption;
  GalleryPhoto({required this.id, required this.ref, required this.date, this.caption = ''});

  Map<String, dynamic> toJson() => {'id': id, 'ref': ref, 'date': date.toIso8601String(), 'caption': caption};
  factory GalleryPhoto.fromJson(Map<String, dynamic> j) =>
      GalleryPhoto(id: j['id'], ref: j['ref'], date: DateTime.parse(j['date']), caption: j['caption'] ?? '');
}

/// Galeria zdjęć psa (pliki na telefonie, lista w valkor_gallery_v1).
class GalleryStore extends ChangeNotifier {
  GalleryStore._();
  static final GalleryStore instance = GalleryStore._();

  static const _key = 'valkor_gallery_v1';
  SharedPreferences? _prefs;
  List<GalleryPhoto> photos = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      photos = [for (final e in (jsonDecode(raw) as List)) GalleryPhoto.fromJson(e)];
    } catch (e) {
      debugPrint('Galeria: błąd odczytu $e');
    }
  }

  Future<void> _save() async {
    photos.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(photos.map((p) => p.toJson()).toList()));
  }

  Future<void> add(Uint8List bytes, {DateTime? date}) async {
    final ref = await FileStore.save(bytes);
    photos.add(GalleryPhoto(id: newId(), ref: ref, date: date ?? DateTime.now()));
    await _save();
  }

  Future<void> update(GalleryPhoto p) => _save();

  Future<void> delete(GalleryPhoto p) async {
    await FileStore.delete(p.ref);
    photos.removeWhere((e) => e.id == p.id);
    await _save();
  }

  Future<void> reset() async {
    for (final p in photos) {
      await FileStore.delete(p.ref);
    }
    photos = [];
    await _save();
  }
}

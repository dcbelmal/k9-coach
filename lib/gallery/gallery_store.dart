import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';
import '../files/file_store.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../storage/dog_doc_guard.dart';
import '../storage/safe_prefs.dart';

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
  List<dynamic> _unreadable = [];
  final guard = DogDocGuard(_key, 'Galeria');

  /// Zapis pliku zdjęcia (podmieniany w testach, np. na opóźniony).
  @visibleForTesting
  static Future<String> Function(Uint8List bytes) saveFile = FileStore.save;

  static (List<GalleryPhoto>, List<dynamic>) _parse(String? raw) {
    if (raw == null) return ([], []);
    return readList(jsonDecode(raw), GalleryPhoto.fromJson);
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    var parsed = (<GalleryPhoto>[], <dynamic>[]);
    await guard.load(_prefs!, DogProfiles.instance.activeId, (raw) => parsed = _parse(raw));
    photos = parsed.$1;
    _unreadable = parsed.$2;
    if (_unreadable.isNotEmpty) {
      final raw = _prefs!.getString(guard.key)!;
      DataHealth.instance.report(StoreIssue(
          key: guard.key,
          store: tr('Galeria'),
          locked: false,
          unreadable: _unreadable.length,
          backupKey: await SafePrefs.preserve(_prefs!, guard.key, raw)));
    }
    notifyListeners();
  }

  String _encode(List<GalleryPhoto> list, List<dynamic> bad) =>
      jsonEncode([...list.map((p) => p.toJson()), ...bad]);

  Future<void> _save() async {
    photos.sort((a, b) => b.date.compareTo(a.date));
    _prefs ??= await SharedPreferences.getInstance();
    try {
      await guard.write(_prefs!, () => _encode(photos, _unreadable), (last) {
        final r = _parse(last);
        photos = r.$1;
        _unreadable = r.$2;
      });
    } finally {
      notifyListeners();
    }
  }

  /// Dodaje zdjęcie psu, który był wybrany w chwili rozpoczęcia zapisu –
  /// także gdy w międzyczasie użytkownik przełączył się na innego psa.
  Future<void> add(Uint8List bytes, {DateTime? date}) {
    final owner = DogProfiles.instance.activeId;
    return DogProfiles.instance.track(() async {
      final ref = await saveFile(bytes);
      final photo = GalleryPhoto(id: newId(), ref: ref, date: date ?? DateTime.now());
      try {
        if (guard.owner == owner) {
          photos.add(photo);
          await _save();
        } else {
          _prefs ??= await SharedPreferences.getInstance();
          await guard.writeOther(_prefs!, owner, (raw) {
            final r = _parse(raw);
            return _encode([...r.$1, photo], r.$2);
          });
        }
      } catch (e) {
        await FileStore.delete(ref); // zapis listy się nie udał – plik nie zostaje bez właściciela
        rethrow;
      }
    });
  }

  Future<void> update(GalleryPhoto p) => _save();

  Future<void> delete(GalleryPhoto p) async {
    photos.removeWhere((e) => e.id == p.id);
    await _save();
    await FileStore.deleteIfUnreferenced(p.ref);
  }
}

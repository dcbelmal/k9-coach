
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_refs.dart';
import 'file_store_io.dart' if (dart.library.js_interop) 'file_store_web.dart' as impl;

/// Zdjęcia dokumentów i sprzętu, trasy GPS: na telefonie w plikach aplikacji
/// (katalog k9_files), w przeglądarce w samej referencji.
class FileStore {
  static Future<void> init() => impl.init();
  @visibleForTesting
  static Future<void> initForTest(String path) => impl.initAt(path);
  static Future<String> save(Uint8List bytes) => impl.save(bytes);
  static Future<String> saveText(String text, {String? name}) => impl.saveText(text, name: name);
  static Future<String?> readText(String ref) => impl.readText(ref);
  static Future<void> delete(String ref) => impl.delete(ref);
  static Widget image(String ref, {BoxFit fit = BoxFit.cover}) => impl.image(ref, fit);
  static Future<List<(String, DateTime)>> listFiles() => impl.listFiles();
  static bool isValidRef(String ref) => impl.isValidRef(ref);
  static bool get hasFiles => impl.hasFiles;

  /// Usuwa plik tylko wtedy, gdy nie wskazuje na niego żaden zapis aplikacji
  /// (żaden pies, kopia odzysku ani szkic treningu).
  static Future<void> deleteIfUnreferenced(String ref) async {
    if (!isValidRef(ref)) return;
    final p = await SharedPreferences.getInstance();
    if (FileRefs.referenced(p).contains(ref)) return;
    if ((await FileRefs.draftRefs()).contains(ref)) return;
    await impl.delete(ref);
  }
}

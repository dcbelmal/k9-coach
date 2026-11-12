import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'file_store_io.dart' if (dart.library.js_interop) 'file_store_web.dart' as impl;

/// Zdjęcia dokumentów i sprzętu: na telefonie w plikach aplikacji, w przeglądarce w pamięci strony.
class FileStore {
  static Future<void> init() => impl.init();
  static Future<String> save(Uint8List bytes) => impl.save(bytes);
  static Future<String> saveText(String text) => impl.saveText(text);
  static Future<String?> readText(String ref) => impl.readText(ref);
  static Future<void> delete(String ref) => impl.delete(ref);
  static Widget image(String ref, {BoxFit fit = BoxFit.cover}) => impl.image(ref, fit);
}

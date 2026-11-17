import 'text_reader_stub.dart' if (dart.library.io) 'text_reader_io.dart' as impl;

/// Rozpoznawanie tekstu ze zdjęcia na telefonie (ML Kit, bez internetu i opłat).
/// W przeglądarce niedostępne – zwraca null.
class TextReader {
  static bool get supported => impl.supported;
  static Future<String?> readFile(String path) => impl.readFile(path);
}

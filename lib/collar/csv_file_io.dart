import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Zapisuje [content] do pliku [name]. Na Androidzie najpierw do folderu
/// Pobrane/Valkor (widoczny w menedżerze plików), a gdy system nie pozwala –
/// do folderu aplikacji. Zwraca pełną ścieżkę albo null.
Future<String?> saveCsvFile(String name, String content) async {
  final dirs = <Future<Directory?> Function()>[
    if (Platform.isAndroid) () async => Directory('/storage/emulated/0/Download/Valkor'),
    if (Platform.isAndroid) getExternalStorageDirectory,
    getApplicationDocumentsDirectory,
  ];
  for (final d in dirs) {
    try {
      final dir = await d();
      if (dir == null) continue;
      await dir.create(recursive: true);
      final f = File('${dir.path}/$name');
      await f.writeAsString(content, flush: true);
      return f.path;
    } catch (_) {
      // Następne miejsce.
    }
  }
  return null;
}

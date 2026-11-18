import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

Directory? _base;
Directory get _dir => _base ?? (throw StateError('FileStore.init'));

/// Dozwolona nazwa pliku w katalogu aplikacji (bez ukośników i „..”).
final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,120}$');

Future<void> init() async {
  final base = await getApplicationDocumentsDirectory();
  await initAt('${base.path}/k9_files');
}

Future<void> initAt(String path) async {
  final d = Directory(path);
  if (!d.existsSync()) d.createSync(recursive: true);
  _base = d;
}

/// Plik dla referencji `file:<nazwa>` albo null, gdy referencja jest nieprawidłowa
/// lub wskazuje poza katalog aplikacji.
File? _fileFor(String ref) {
  if (_base == null || !ref.startsWith('file:')) return null;
  final name = ref.substring(5);
  if (!_safeName.hasMatch(name) || name.contains('..')) return null;
  return File('${_dir.path}/$name');
}

bool isValidRef(String ref) => _fileFor(ref) != null;

/// Zapis przez plik tymczasowy i zmianę nazwy – przerwanie nie zostawia połowy pliku.
Future<void> _atomicWrite(File f, Future<void> Function(File tmp) write) async {
  final tmp = File('${f.path}.tmp');
  try {
    await write(tmp);
    await tmp.rename(f.path);
  } catch (e) {
    try {
      if (tmp.existsSync()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

Future<String> save(Uint8List bytes) async {
  final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
  await _atomicWrite(File('${_dir.path}/$name'), (t) => t.writeAsBytes(bytes, flush: true));
  return 'file:$name';
}

Future<void> delete(String ref) async {
  final f = _fileFor(ref);
  if (f != null && f.existsSync()) await f.delete();
}

Widget image(String ref, BoxFit fit) {
  final f = _fileFor(ref);
  if (f != null) {
    return Image.file(f, fit: fit, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)));
  }
  return const Center(child: Icon(Icons.broken_image_outlined));
}

/// Zapis tekstu. Z [name] zapis jest powtarzalny: ta sama nazwa nadpisuje ten sam plik.
Future<String> saveText(String text, {String? name}) async {
  final n = name ?? 'trk_${DateTime.now().microsecondsSinceEpoch}.json';
  if (!_safeName.hasMatch(n)) throw ArgumentError('name');
  await _atomicWrite(File('${_dir.path}/$n'), (t) => t.writeAsString(text, flush: true));
  return 'file:$n';
}

Future<String?> readText(String ref) async {
  final f = _fileFor(ref);
  return f != null && f.existsSync() ? f.readAsString() : null;
}

/// Pliki w katalogu aplikacji: (referencja, czas modyfikacji).
Future<List<(String, DateTime)>> listFiles() async {
  final out = <(String, DateTime)>[];
  if (_base == null || !_dir.existsSync()) return out;
  for (final e in _dir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last;
    if (!_safeName.hasMatch(name) || name.endsWith('.tmp')) continue;
    out.add(('file:$name', e.statSync().modified));
  }
  return out;
}

bool get hasFiles => true;

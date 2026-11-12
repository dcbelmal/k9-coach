import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

late Directory _dir;

Future<void> init() async {
  final base = await getApplicationDocumentsDirectory();
  _dir = Directory('${base.path}/k9_files');
  if (!_dir.existsSync()) _dir.createSync(recursive: true);
}

Future<String> save(Uint8List bytes) async {
  final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
  await File('${_dir.path}/$name').writeAsBytes(bytes);
  return 'file:$name';
}

Future<void> delete(String ref) async {
  if (!ref.startsWith('file:')) return;
  final f = File('${_dir.path}/${ref.substring(5)}');
  if (f.existsSync()) await f.delete();
}

Widget image(String ref, BoxFit fit) {
  if (ref.startsWith('file:')) {
    return Image.file(File('${_dir.path}/${ref.substring(5)}'), fit: fit,
        errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)));
  }
  return const Center(child: Icon(Icons.broken_image_outlined));
}

Future<String> saveText(String text) async {
  final name = 'trk_${DateTime.now().microsecondsSinceEpoch}.json';
  await File('${_dir.path}/$name').writeAsString(text);
  return 'file:$name';
}

Future<String?> readText(String ref) async {
  if (!ref.startsWith('file:')) return null;
  final f = File('${_dir.path}/${ref.substring(5)}');
  return f.existsSync() ? f.readAsString() : null;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

Future<void> init() async {}

Future<String> save(Uint8List bytes) async => 'b64:${base64Encode(bytes)}';

Future<void> delete(String ref) async {}

Widget image(String ref, BoxFit fit) {
  if (ref.startsWith('b64:')) return Image.memory(base64Decode(ref.substring(4)), fit: fit);
  return const Center(child: Icon(Icons.broken_image_outlined));
}

Future<String> saveText(String text) async => 'txt:$text';

Future<String?> readText(String ref) async => ref.startsWith('txt:') ? ref.substring(4) : null;

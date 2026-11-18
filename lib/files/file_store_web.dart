import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

// W przeglądarce plik jest zapisany w samej referencji (base64), razem z danymi.

Future<void> init() async {}

Future<void> initAt(String path) async {}

bool isValidRef(String ref) => ref.startsWith('b64:') || ref.startsWith('txt:');

Future<String> save(Uint8List bytes) async => 'b64:${base64Encode(bytes)}';

Future<void> delete(String ref) async {}

Widget image(String ref, BoxFit fit) {
  if (ref.startsWith('b64:')) {
    try {
      return Image.memory(base64Decode(ref.substring(4)), fit: fit,
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)));
    } catch (_) {}
  }
  return const Center(child: Icon(Icons.broken_image_outlined));
}

Future<String> saveText(String text, {String? name}) async => 'txt:$text';

Future<String?> readText(String ref) async => ref.startsWith('txt:') ? ref.substring(4) : null;

Future<List<(String, DateTime)>> listFiles() async => const [];

bool get hasFiles => false;

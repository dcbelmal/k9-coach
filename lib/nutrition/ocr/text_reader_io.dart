import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

bool get supported => Platform.isAndroid || Platform.isIOS;

Future<String?> readFile(String path) async {
  if (!supported) return null;
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final res = await r.processImage(InputImage.fromFilePath(path));
    // Najpierw tekst złożony w wiersze (tabela „nazwa … wartość” w jednej linii),
    // potem oryginalny odczyt ML Kit jako zapas.
    return '${_rows(res)}\n\n${res.text}';
  } catch (e) {
    debugPrint('OCR: $e');
    return null;
  } finally {
    await r.close();
  }
}

/// Składa linie tekstu leżące na tej samej wysokości w jeden wiersz (od lewej do prawej).
/// ML Kit często czyta tabele kolumnami, przez co nazwy oddzielają się od liczb.
String _rows(RecognizedText res) {
  final lines = [for (final b in res.blocks) ...b.lines]..sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
  final rows = <List<TextLine>>[];
  for (final l in lines) {
    final cy = l.boundingBox.center.dy;
    final h = l.boundingBox.height;
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final ref = row.first.boundingBox;
      if ((ref.center.dy - cy).abs() < 0.5 * (h < ref.height ? h : ref.height)) {
        row.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return rows.map((r) {
    r.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    return r.map((l) => l.text).join(' ');
  }).join('\n');
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

bool get supported => Platform.isAndroid || Platform.isIOS;

Future<String?> readFile(String path) async {
  if (!supported) return null;
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final res = await r.processImage(InputImage.fromFilePath(path));
    return res.text;
  } catch (e) {
    debugPrint('OCR: $e');
    return null;
  } finally {
    await r.close();
  }
}

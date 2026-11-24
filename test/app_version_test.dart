import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/app_version.dart';

void main() {
  test('wersja w aplikacji = wersja z pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final v = line.substring('version:'.length).trim().split('+').first;
    expect(appVersion, v);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens take colours from AppColors or the theme, so a status reads the
/// same everywhere and a dark theme has one place to change. Plain white,
/// black and transparent stay allowed for now.
void main() {
  test('no raw colours outside the palette', () {
    final raw = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');
    final material = RegExp(
      r'(?<![A-Za-z_.])Colors\.(?!white|black|transparent)[a-zA-Z]+',
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll('\\', '/');
      if (path.endsWith('app/theme/app_colors.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i]) || material.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use an AppColors token (or add one) instead of:\n'
          '${offenders.join('\n')}',
    );
  });
}

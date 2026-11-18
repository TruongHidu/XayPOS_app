import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The dependency rules the README and docs describe, checked on imports:
///
/// * `lib/core/ui` is shared by every feature, so it never imports one.
///   Screens are wired into the shell from `lib/app/shell`, the composition
///   root, which may import features.
/// * A feature's `domain` layer is plain Dart: no Flutter, Riverpod or Dio.
void main() {
  List<String> violations(String dir, bool Function(String) forbidden) {
    final found = <String>[];
    for (final file in Directory(dir).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll('\\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('import ')) continue;
        if (forbidden(line)) found.add('$path:${i + 1}: $line');
      }
    }
    return found;
  }

  test('core/ui does not import features', () {
    expect(
      violations('lib/core/ui', (line) => line.contains('features/')),
      isEmpty,
    );
  });

  test('domain layers stay free of Flutter, Riverpod and Dio', () {
    final found = <String>[];
    for (final feature in Directory('lib/features').listSync()) {
      final domain = Directory('${feature.path}/domain');
      if (!domain.existsSync()) continue;
      found.addAll(
        violations(
          domain.path,
          (line) => RegExp(
            r"package:(flutter|flutter_riverpod|riverpod|dio)/",
          ).hasMatch(line),
        ),
      );
    }
    expect(found, isEmpty);
  });
}

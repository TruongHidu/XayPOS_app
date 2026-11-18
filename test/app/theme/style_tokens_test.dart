import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens take sizes, corners and neutral colours from the design system
/// (`lib/app/theme`, see docs/ui-design-system.md), so the app keeps one
/// look and a dark theme has one place to change.
///
/// This is a ratchet: each count may only go down. When a change removes
/// some, lower the matching ceiling here in the same commit; a change that
/// adds one fails and should use a token instead.
const _ceilings = {
  // `fontSize: 13` in a screen instead of a TextTheme style.
  'literal fontSize': 113,
  // `BorderRadius.circular(12)` instead of `AppRadius.mdAll`.
  'literal corner radius': 0,
  // `AppColors.grey600` instead of a colour-scheme role such as
  // `colorScheme.onSurfaceVariant`; fixed greys block a dark theme.
  'fixed neutral grey': 127,
};

final _patterns = {
  'literal fontSize': RegExp(r'fontSize:\s*\d'),
  'literal corner radius': RegExp(r'BorderRadius\.circular\(\s*\d'),
  'fixed neutral grey': RegExp(r'AppColors\.grey\d+'),
};

void main() {
  test('screens do not add raw sizes, corners or greys', () {
    final counts = {for (final name in _patterns.keys) name: 0};
    final where = {for (final name in _patterns.keys) name: <String>[]};
    for (final dir in ['lib/features', 'lib/core/ui']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final path = file.path.replaceAll('\\', '/');
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final MapEntry(key: name, value: pattern) in _patterns.entries) {
            final hits = pattern.allMatches(lines[i]).length;
            if (hits == 0) continue;
            counts[name] = counts[name]! + hits;
            where[name]!.add('$path:${i + 1}');
          }
        }
      }
    }
    for (final MapEntry(key: name, value: ceiling) in _ceilings.entries) {
      final count = counts[name]!;
      expect(
        count,
        lessThanOrEqualTo(ceiling),
        reason:
            '$name: $count found, at most $ceiling allowed. Use a token from '
            'lib/app/theme instead. Latest:\n'
            '${where[name]!.reversed.take(10).join('\n')}',
      );
    }
  });
}

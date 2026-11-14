import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/theme/app_colors.dart';
import 'package:pos_saas_app/app/theme/app_status_colors.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/app/theme/app_typography.dart';

void main() {
  final theme = AppTheme.light;

  test('brand colours and neutral surfaces are pinned', () {
    final scheme = theme.colorScheme;
    expect(scheme.primary, AppColors.primary);
    expect(scheme.error, AppColors.danger);
    expect(scheme.surface, Colors.white);
    expect(scheme.outlineVariant, AppColors.grey200);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
  });

  test('cards are flat white with a hairline border', () {
    final card = theme.cardTheme;
    expect(card.elevation, 0);
    expect(card.color, Colors.white);
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.side.color, AppColors.grey200);
  });

  test('tone colours are registered and readable from a context', () {
    expect(theme.extension<AppStatusColors>(), isNotNull);
    expect(
      AppStatusColors.light.of(AppTone.success).foreground,
      AppColors.success,
    );
    for (final tone in AppTone.values) {
      final colors = AppStatusColors.light.of(tone);
      expect(colors.foreground, isNot(colors.background), reason: '$tone');
    }
  });

  testWidgets('context.tone follows the theme', (tester) async {
    late ToneColors danger;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            danger = context.tone(AppTone.danger);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(danger.background, AppColors.dangerSoft);
  });

  test('the bundled font family is declared and its files exist', () {
    expect(theme.textTheme.bodyMedium?.fontFamily, AppTypography.fontFamily);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${AppTypography.fontFamily}'));
    final assets = RegExp(
      r'asset: (assets/fonts/\S+\.ttf)',
    ).allMatches(pubspec).map((m) => m.group(1)!).toList();
    expect(assets, hasLength(4));
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });
}

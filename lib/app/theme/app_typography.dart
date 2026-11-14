import 'package:flutter/material.dart';

/// Type scale: Material 3 sizes and line heights with firmer weights for
/// titles and labels, so headings and buttons stand out without growing.
/// Only weights (and a smaller [TextTheme.titleLarge] for app bars and
/// dialogs) change, so layouts measured against the Material scale hold.
/// Colours come from the colour scheme, so these styles carry none.
abstract final class AppTypography {
  /// Family registered in pubspec.yaml; falls back to the platform font
  /// when the asset is missing.
  static const fontFamily = 'BeVietnamPro';

  static const textTheme = TextTheme(
    headlineMedium: TextStyle(fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontWeight: FontWeight.w600),
    labelLarge: TextStyle(fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontWeight: FontWeight.w600),
  );
}

/// Styles beyond the Material scale, derived from the theme's [TextTheme].
extension AppTextStyles on TextTheme {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Amounts in lists and cards: digits line up in columns.
  TextStyle get money =>
      (titleSmall ?? const TextStyle()).copyWith(fontFeatures: _tabular);

  /// Totals and KPI values.
  TextStyle get moneyLarge => (titleLarge ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  /// Secondary line under a title: timestamps, codes, hints.
  TextStyle get caption => bodySmall ?? const TextStyle(fontSize: 12);
}

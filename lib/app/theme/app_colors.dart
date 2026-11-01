import 'package:flutter/material.dart';

/// Colours with a fixed meaning. Screens use these instead of raw values, so
/// "còn hàng" or "cảnh báo" reads the same everywhere in the app.
abstract final class AppColors {
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF3F4F6);
  static const grey200 = Color(0xFFE5E7EB);
  static const grey300 = Color(0xFFD1D5DB);
  static const grey400 = Color(0xFF9CA3AF);
  static const grey500 = Color(0xFF6B7280);
  static const grey600 = Color(0xFF4B5563);
  static const grey700 = Color(0xFF374151);
  static const grey800 = Color(0xFF1F2937);
  static const grey900 = Color(0xFF111827);

  static const success = Color(0xFF0F766E);
  static const successSoft = Color(0xFFCCFBF1);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3C7);
  static const warningTint = Color(0xFFFFFAF2);
  static const warningBorder = Color(0xFFFDE68A);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const info = Color(0xFF0284C7);
  static const infoSoft = Color(0xFFE0F2FE);
}

import 'package:flutter/material.dart';

/// Colours with a fixed meaning. Screens use these instead of raw values, so
/// "còn hàng" or "cảnh báo" reads the same everywhere in the app.
///
/// Each status comes as a set: the strong colour for icons and text, a soft
/// background, a lighter tint for large areas and a border. `*Strong` keeps
/// small text readable (at least 4.5:1) on the matching soft background.
/// A guard test fails when a screen adds a raw colour instead of a token.
abstract final class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────
  /// Brand blue; [AppTheme] pins the colour scheme's primary to it.
  static const primary = Color(0xFF0863BE);
  static const primaryLight = Color(0xFF0877D9);
  static const primaryDark = Color(0xFF0754AB);

  /// Selected item backgrounds, image placeholders, "đang phục vụ" chips.
  static const primarySoft = Color(0xFFE8F1FB);
  static const primaryBorder = Color(0xFFB9D3F0);

  /// Text selection highlight.
  static const selection = Color(0x330878F9);

  // ── Neutrals ──────────────────────────────────────────────────────────
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

  // ── Surfaces ──────────────────────────────────────────────────────────
  /// Page background behind white cards and panels.
  static const background = Color(0xFFF4F6F8);

  /// Between [grey100] and [grey200]: hovered rows, pressed tiles.
  static const surfaceHigh = Color(0xFFECEEF2);

  // ── Status ────────────────────────────────────────────────────────────
  /// Done, in stock, paid, has an order.
  static const success = Color(0xFF0F766E);
  static const successSoft = Color(0xFFCCFBF1);
  static const successTint = Color(0xFFF0FDF4);
  static const successBorder = Color(0xFFBBF7D0);

  /// Needs attention: unconfirmed, waiting, notes, low stock.
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3C7);
  static const warningTint = Color(0xFFFFFAF2);
  static const warningBorder = Color(0xFFFDE68A);

  /// Errors, cancellations, overdue.
  static const danger = Color(0xFFDC2626);
  static const dangerStrong = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const dangerBorder = Color(0xFFFECACA);

  /// Neutral information: QR requests, in progress.
  static const info = Color(0xFF0284C7);
  static const infoStrong = Color(0xFF0369A1);
  static const infoSoft = Color(0xFFE0F2FE);
  static const infoBorder = Color(0xFFBAE6FD);

  // ── Money ─────────────────────────────────────────────────────────────
  static const income = Color(0xFF1B7F3B);

  /// [income] on a dark background.
  static const incomeOnDark = Color(0xFF6FD58B);

  // ── Categories ────────────────────────────────────────────────────────
  /// For charts and status chips that need more distinct hues than the
  /// statuses above; never to signal success, warning or danger.
  static const accentOrange = Color(0xFFEA580C);

  /// [accentOrange] dark enough for small text on [accentOrangeSoft].
  static const accentOrangeStrong = Color(0xFFC2410C);
  static const accentOrangeSoft = Color(0xFFFFEDD5);
  static const accentCyan = Color(0xFF0E7490);
  static const accentCyanSoft = Color(0xFFCFFAFE);
  static const accentViolet = Color(0xFF7C3AED);
  static const accentVioletSoft = Color(0xFFEDE9FE);
  static const accentIndigo = Color(0xFF4F46E5);
  static const accentIndigoSoft = Color(0xFFE0E7FF);
}

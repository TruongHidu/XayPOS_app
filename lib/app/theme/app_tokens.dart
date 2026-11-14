/// Layout tokens shared by every screen, so gaps, corners and breakpoints
/// read the same across features. Colours live in `app_colors.dart`, text
/// styles in `app_typography.dart`.
library;

import 'package:flutter/widgets.dart';

/// Spacing scale on a 4 px grid. Use these for padding, gaps and
/// `SizedBox` spacers instead of literal numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal page gutter: 16 on phones, 24 from tablet width.
  static double pageGutter(double width) =>
      width >= AppBreakpoints.medium ? xxl : lg;

  /// Page padding for a screen body of the given [width].
  static EdgeInsets pagePadding(double width) =>
      EdgeInsets.all(pageGutter(width));
}

/// Corner radii. Cards and panels use [md]; inputs and buttons [button];
/// dialogs [lg]; bottom sheets [xl]; chips and badges [sm] or [pill].
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double button = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const buttonAll = BorderRadius.all(Radius.circular(button));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const xlAll = BorderRadius.all(Radius.circular(xl));
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Window-width breakpoints (Material 3 window size classes).
///
/// * compact: phones, `< medium`
/// * medium: tablets in portrait and large phones in landscape
/// * expanded: tablets in landscape and POS screens, `>= expanded`
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;

  /// Composer and append screens show menu and cart side by side from here.
  static const double orderSplit = 840;

  /// Wide data tables (inventory, recipes) switch from cards to columns.
  static const double wideTable = 1100;

  static bool isCompact(double width) => width < medium;
  static bool isMedium(double width) => width >= medium && width < expanded;
  static bool isExpanded(double width) => width >= expanded;
}

/// Animation durations.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 300);
}

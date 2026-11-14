import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_status_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'slide_page_transitions.dart';

/// The app's light theme: brand blue on a soft grey page, white cards with a
/// thin border instead of shadows. Component themes here keep screens from
/// styling buttons, fields, dialogs and chips one by one.
abstract final class AppTheme {
  static const primaryColor = AppColors.primary;

  static ThemeData get light {
    // fromSeed shifts the tone, so pin primary to the exact brand blue, and
    // pin surfaces to the neutral greys so they carry no blue tint.
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ).copyWith(
          primary: primaryColor,
          onPrimary: Colors.white,
          error: AppColors.danger,
          onError: Colors.white,
          errorContainer: AppColors.dangerSoft,
          onErrorContainer: AppColors.dangerStrong,
          surface: Colors.white,
          onSurface: AppColors.grey900,
          onSurfaceVariant: AppColors.grey600,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: AppColors.grey50,
          surfaceContainer: AppColors.grey100,
          surfaceContainerHigh: AppColors.surfaceHigh,
          surfaceContainerHighest: AppColors.grey200,
          outline: AppColors.grey500,
          outlineVariant: AppColors.grey200,
          surfaceTint: Colors.transparent,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: AppTypography.textTheme,
    );
    final text = base.textTheme;

    final fieldBorder = WidgetStateBorderSide.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return const BorderSide(color: AppColors.grey200);
      }
      if (states.contains(WidgetState.error)) {
        return BorderSide(
          color: AppColors.danger,
          width: states.contains(WidgetState.focused) ? 1.6 : 1,
        );
      }
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: primaryColor, width: 1.6);
      }
      if (states.contains(WidgetState.hovered)) {
        return const BorderSide(color: AppColors.grey400);
      }
      return const BorderSide(color: AppColors.grey300);
    });

    const buttonShape = RoundedRectangleBorder(
      borderRadius: AppRadius.buttonAll,
    );
    const buttonMinSize = Size(64, 44);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: Colors.white,
      dividerColor: AppColors.grey200,
      // Ripples without the sparkle shader, which costs a compile on first
      // tap on low-end Android devices.
      splashFactory: InkRipple.splashFactory,
      extensions: const [AppStatusColors.light],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SlidePageTransitionsBuilder(),
          // Keeps the native swipe-back gesture.
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: SlidePageTransitionsBuilder(),
          TargetPlatform.windows: SlidePageTransitionsBuilder(),
          TargetPlatform.linux: SlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: SlidePageTransitionsBuilder(),
        },
      ),
      // White bar with a hairline under it; it keeps its colour while
      // content scrolls under it.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.grey900,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: AppColors.grey200)),
        titleTextStyle: text.titleLarge?.copyWith(color: AppColors.grey900),
        iconTheme: const IconThemeData(color: AppColors.grey700),
        actionsIconTheme: const IconThemeData(color: AppColors.grey700),
      ),
      // Selected bottom tab: no pill, icon and label both in primary.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primarySoft,
        selectedIconTheme: const IconThemeData(color: primaryColor),
        unselectedIconTheme: const IconThemeData(color: AppColors.grey600),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: primaryColor),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: AppColors.grey600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: AppColors.grey200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.grey50
              : Colors.white,
        ),
        border: const OutlineInputBorder(borderRadius: AppRadius.buttonAll),
        // Filled and outlined fields both draw their border from these.
        activeIndicatorBorder: fieldBorder,
        outlineBorder: fieldBorder,
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.grey400),
        prefixIconColor: AppColors.grey500,
        suffixIconColor: AppColors.grey500,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          foregroundColor: AppColors.grey800,
          side: const BorderSide(color: AppColors.grey300),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          side: const BorderSide(color: AppColors.grey300),
          selectedBackgroundColor: AppColors.primarySoft,
          selectedForegroundColor: AppColors.primaryDark,
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.primarySoft,
        checkmarkColor: AppColors.primaryDark,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryBorder
                : AppColors.grey300,
          ),
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        labelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.grey800,
        ),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: AppColors.primaryDark,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: AppColors.grey600,
        indicatorColor: primaryColor,
        dividerColor: AppColors.grey200,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: text.titleLarge?.copyWith(color: AppColors.grey900),
        contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.grey700),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: AppColors.grey200),
        ),
        textStyle: text.bodyMedium?.copyWith(color: AppColors.grey900),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.grey900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.primarySoft,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.buttonAll),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.grey800,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs + 2)),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.grey600,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.grey200,
        thickness: 1,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(AppColors.grey50),
        headingTextStyle: text.labelLarge?.copyWith(color: AppColors.grey700),
        dataTextStyle: text.bodyMedium?.copyWith(color: AppColors.grey900),
        dividerThickness: 1,
      ),
      checkboxTheme: const CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: AppColors.primarySoft,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.danger,
        textColor: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: AppColors.selection,
        selectionHandleColor: primaryColor,
      ),
    );
  }
}

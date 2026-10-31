import 'package:flutter/material.dart';

import 'slide_page_transitions.dart';

abstract final class AppTheme {
  static const primaryColor = Color(0xFF0863BE);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      fontFamily: 'Roboto',
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
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: Color(0x330878F9),
        selectionHandleColor: primaryColor,
      ),
    );
  }
}

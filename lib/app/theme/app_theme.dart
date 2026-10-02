import 'package:flutter/material.dart';

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
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: Color(0x330878F9),
        selectionHandleColor: primaryColor,
      ),
    );
  }
}

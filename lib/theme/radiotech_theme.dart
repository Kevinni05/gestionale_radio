import 'package:flutter/material.dart';
import 'radiotech_backdrop.dart';

/// Shared with the web Signal / Raycast theme. Status colors stay semantic.
abstract final class RadioTechTheme {
  static const canvas = Color(0xFF08090D);
  static const surface = Color(0xCC191A24);
  static const border = Color(0x33B8B3DC);
  static const coral = Color(0xFFFF6363);
  static const ink = Color(0xFF151518);
  static const mist = Color(0xFFE6E6E6);
  static const muted = Color(0xFFB9BBC9);

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: coral,
          brightness: Brightness.dark,
        ).copyWith(
          primary: coral,
          onPrimary: ink,
          secondary: mist,
          onSecondary: ink,
          surface: surface,
          onSurface: const Color(0xFFF5F5F7),
          onSurfaceVariant: muted,
          outline: border,
          surfaceContainer: const Color(0xFF20212B),
          surfaceContainerHighest: const Color(0xFF292A34),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final action =
        ElevatedButton.styleFrom(
          backgroundColor: mist,
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.pressed) ? 5 : 0,
          ),
          shadowColor: const WidgetStatePropertyAll(Color(0x99FF6363)),
          overlayColor: const WidgetStatePropertyAll(Color(0x22FF6363)),
          animationDuration: const Duration(milliseconds: 180),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      colorScheme: scheme,
      primaryColor: coral,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: RadioTechPageTransitions(),
          TargetPlatform.iOS: RadioTechPageTransitions(),
          TargetPlatform.windows: RadioTechPageTransitions(),
          TargetPlatform.macOS: RadioTechPageTransitions(),
          TargetPlatform.linux: RadioTechPageTransitions(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xDC10111A),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFFF5F5F7),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: muted, fontSize: 14),
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        helperStyle: const TextStyle(color: muted, height: 1.4),
        helperMaxLines: 3,
        errorMaxLines: 3,
        floatingLabelStyle: const TextStyle(color: coral),
        filled: true,
        fillColor: const Color(0xA6111219),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: coral, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: action),
      filledButtonTheme: FilledButtonThemeData(style: action),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: mist,
          shape: shape,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: mist),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0x991B1C26),
        selectedColor: const Color(0x55452324),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          color: mist,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xEC10111A),
        indicatorColor: Color(0x55452324),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF181922),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xF2181922),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF292A34),
        contentTextStyle: TextStyle(fontFamily: 'Inter', color: mist),
      ),
      dividerTheme: const DividerThemeData(color: border),
      visualDensity: VisualDensity.standard,
    );
  }
}

import 'package:flutter/material.dart';

/// Compact, desktop-oriented visual system used only by the Windows edition.
/// Android keeps its existing Material styling.
ThemeData buildWindowsTheme() {
  const ink = Color(0xFF263442);
  const muted = Color(0xFF667482);
  const accent = Color(0xFF24647A);
  const border = Color(0xFFD9E0E6);
  const surface = Color(0xFFFFFFFF);
  const canvas = Color(0xFFF4F6F8);

  const scheme = ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    secondary: Color(0xFF547D8B),
    onSecondary: Colors.white,
    surface: surface,
    onSurface: ink,
    error: Color(0xFFB42318),
    onError: Colors.white,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: canvas,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 48,
      backgroundColor: Color(0xFFF7F9FB),
      foregroundColor: ink,
      titleTextStyle: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(size: 18, color: muted),
    ),
    iconTheme: const IconThemeData(size: 18, color: muted),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 13, color: ink),
      bodyMedium: TextStyle(fontSize: 12, color: ink),
      bodySmall: TextStyle(fontSize: 11, color: muted),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      labelStyle: const TextStyle(fontSize: 12, color: muted),
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF89939D)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: accent, width: 1.2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), side: const BorderSide(color: border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(30, 30), maximumSize: const Size(34, 34), padding: const EdgeInsets.all(6), iconSize: 17, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
    listTileTheme: const ListTileThemeData(dense: true, minTileHeight: 38, minVerticalPadding: 2, horizontalTitleGap: 8, minLeadingWidth: 22, contentPadding: EdgeInsets.symmetric(horizontal: 10), iconColor: muted, textColor: ink),
    cardTheme: CardThemeData(color: surface, elevation: 0, margin: const EdgeInsets.all(4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: const BorderSide(color: border))),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    dataTableTheme: const DataTableThemeData(headingRowHeight: 38, dataRowMinHeight: 34, dataRowMaxHeight: 42, horizontalMargin: 12, columnSpacing: 18, headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink), dataTextStyle: TextStyle(fontSize: 12, color: ink), dividerThickness: 0.6),
    dialogTheme: DialogThemeData(backgroundColor: surface, elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink), contentTextStyle: const TextStyle(fontSize: 12, color: ink)),
    popupMenuTheme: PopupMenuThemeData(textStyle: const TextStyle(fontSize: 12, color: ink), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, contentTextStyle: const TextStyle(fontSize: 12, color: Colors.white), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    tabBarTheme: const TabBarThemeData(labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600), unselectedLabelStyle: TextStyle(fontSize: 12), indicatorSize: TabBarIndicatorSize.label),
    // Keep desktop scroll affordances visible across all Windows screens.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: MaterialStatePropertyAll(true),
      thickness: MaterialStatePropertyAll(8),
      thumbColor: MaterialStatePropertyAll(Color(0xFF84919C)),
      radius: Radius.circular(4),
      interactive: true,
    ),
  );
}

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Paleta K9 Coach: ciemne tło, karty grafitowe, akcent pomarańczowy.
class K9 {
  static const bg = Color(0xFF0B0B0C);
  static const card = Color(0xFF161618);
  static const cardHi = Color(0xFF1E1E21);
  static const border = Color(0xFF26262A);
  static const orange = Color(0xFFF5821F);
  static const orangeDeep = Color(0xFFD9620B);
  static const text = Color(0xFFF5F5F7);
  static const muted = Color(0xFF9A9AA1);
  static const faint = Color(0xFF5E5E66);
  static const green = Color(0xFF34C759);
  static const yellow = Color(0xFFFFC53D);
  static const red = Color(0xFFFF453A);
  static const blue = Color(0xFF5E8BFF);

  static const radius = 22.0;

  static const orangeGradient = LinearGradient(
    colors: [Color(0xFFFF9A3C), orange, orangeDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: orange,
        secondary: orange,
        surface: card,
        onPrimary: Colors.black,
        onSurface: text,
        error: red,
      ),
    );
    final textTheme = base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: text,
      displayColor: text,
    );
    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 22),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardHi,
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: orange, width: 1.4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: orange,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: orange),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.black : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? orange : cardHi),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cardHi,
        contentTextStyle: TextStyle(color: text),
      ),
      dividerColor: border,
    );
  }
}

// ---------------------------------------------------------------------------
// Formatowanie po polsku
// ---------------------------------------------------------------------------

String fmtDate(DateTime d) => DateFormat('d MMM yyyy', 'pl').format(d);
String fmtDateShort(DateTime d) => DateFormat('d MMM', 'pl').format(d);
String fmtDayMonth(DateTime d) => DateFormat('d.MM', 'pl').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm', 'pl').format(d);
String fmtWeekday(DateTime d) => DateFormat('EEE', 'pl').format(d);
String fmtMonthYear(DateTime d) {
  final s = DateFormat('LLLL yyyy', 'pl').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String fmtKm(double km) => km >= 100 ? km.toStringAsFixed(0) : km.toStringAsFixed(1).replaceAll('.', ',');
String fmtNum(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

String fmtDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "za 10 dni", "jutro", "dziś", "3 dni temu".
String relDays(DateTime d) {
  final now = DateTime.now();
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(d.year, d.month, d.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'dziś';
  if (diff == 1) return 'jutro';
  if (diff == -1) return 'wczoraj';
  if (diff > 1) return 'za $diff dni';
  return '${-diff} dni temu';
}

String fmtDurationShort(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

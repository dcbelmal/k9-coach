import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'l10n/l10n.dart';

/// Paleta Valkor Coach: ciemne tło, karty grafitowe, akcent pomarańczowy.
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

  // Marka Valkor (logo Valkor Canis): różowe złoto na czarnym tle.
  static const brandBg = Color(0xFF0A0908);
  static const gold = Color(0xFFDDB59A);
  static const goldLight = Color(0xFFE8C6AE);
  static const goldSoft = Color(0xFFCDB3A1);
  static const goldDeep = Color(0xFF9E6E55);

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
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16),
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
// Formatowanie zależne od języka aplikacji
// ---------------------------------------------------------------------------

String get _loc => L10n.instance.code;
String fmtDate(DateTime d) => DateFormat.yMMMd(_loc).format(d);
String fmtDateShort(DateTime d) => DateFormat.MMMd(_loc).format(d);
String fmtDayMonth(DateTime d) => _loc == 'pl' ? DateFormat('d.MM').format(d) : DateFormat.Md(_loc).format(d);
String fmtTime(DateTime d) => DateFormat.Hm(_loc).format(d);
String fmtWeekday(DateTime d) => DateFormat.E(_loc).format(d);
String fmtMonthYear(DateTime d) {
  final s = DateFormat.yMMMM(_loc).format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String _dec(String s) => L10n.instance.decimalComma ? s.replaceAll('.', ',') : s;
String fmtKm(double km) => km >= 100 ? km.toStringAsFixed(0) : _dec(km.toStringAsFixed(1));
String fmtNum(double v, [int digits = 1]) => _dec(v.toStringAsFixed(digits));

String fmtDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return tr('{0} min', [m]);
  return m == 0 ? '$h h' : tr('{0} h {1} min', [h, m]);
}

/// "za 10 dni", "jutro", "dziś", "3 dni temu".
String relDays(DateTime d) {
  final now = DateTime.now();
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(d.year, d.month, d.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return tr('dziś');
  if (diff == 1) return 'jutro';
  if (diff == -1) return 'wczoraj';
  if (diff > 1) return tr('za {0} dni', [diff]);
  return tr('{0} dni temu', [-diff]);
}

String fmtDurationShort(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return tr('{0} min', [m]);
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

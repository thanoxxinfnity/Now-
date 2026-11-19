import 'package:material_ui/material_ui.dart';

/// Design tokens, modelled on the scale of a clean dark "studio" UI:
/// canvas / card / field surfaces, 4-6-8 radii, one blue accent.
class Tk {
  static const canvas = Color(0xFF121316);
  static const chrome = Color(0xFF101014);
  static const card = Color(0xFF1B1C1F);
  static const raised = Color(0xFF222325);
  static const field = Color(0xFF222326);
  static const border = Color(0xFF343436);
  static const hover = Color(0xFF2A2B2E);
  static const pressed = Color(0xFF333437);
  static const text = Color(0xFFF2F1EE);
  static const dim = Color(0xFFB3B3B2);
  static const faint = Color(0xFF8D8D8D);
  static const accent = Color(0xFF2D81FF);
  static const accentInk = Color(0xFF74AAFF);
  static const accentSoft = Color(0x2C2D81FF);
  static const danger = Color(0xFFFF6259);
  static const success = Color(0xFF5BBF8F);
  static const warn = Color(0xFFE0A23A);
  static const code = Color(0xFF060607);
  // "Limitless" palette used by the orb / aura animations.
  static const blue = Color(0xFF3D8BFF);
  static const red = Color(0xFFFF4D5E);
  static const violet = Color(0xFF8B5CF6);

  static const rSm = 4.0, r = 6.0, rLg = 8.0, rXl = 14.0;
  static const double gap = 8;
}

TextStyle ts(double size,
    {double w = 400, Color color = Tk.text, double? h, bool mono = false}) {
  return TextStyle(
    fontFamily: mono ? 'JetBrainsMono' : 'Figtree',
    fontSize: size,
    height: h,
    color: color,
    fontWeight: FontWeight.values[((w ~/ 100) - 1).clamp(0, 8)],
    fontVariations: mono ? null : [FontVariation('wght', w)],
  );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Tk.canvas,
    canvasColor: Tk.canvas,
    colorScheme: const ColorScheme.dark(
      primary: Tk.accent,
      secondary: Tk.accentInk,
      surface: Tk.card,
      error: Tk.danger,
      onSurface: Tk.text,
    ),
    dividerColor: Tk.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: base.textTheme.apply(fontFamily: 'Figtree', bodyColor: Tk.text, displayColor: Tk.text),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tk.raised,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: ts(14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tk.rLg),
          side: const BorderSide(color: Tk.border)),
    ),
  );
}

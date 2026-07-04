import 'package:flutter/material.dart';

/// Modern pastel palette for the redesigned UI (visual only â€” no screen
/// logic changed). Old names (primary/secondary/accent/background/surface)
/// are kept so every existing widget that references AppColors.* keeps
/// compiling; they now point at the new palette's equivalents.
class AppColors {
  AppColors._();

  // --- New pastel palette ---
  static const Color purple = Color(0xFF6C63FF);
  static const Color purpleLight = Color(0xFFEEEAFE);

  static const Color orange = Color(0xFFFFB088);
  static const Color orangeLight = Color(0xFFFFF1E8);

  static const Color blue = Color(0xFF6B8AF7);
  static const Color blueLight = Color(0xFFEAF1FF);

  static const Color green = Color(0xFF50C878);
  static const Color greenLight = Color(0xFFE8FFF0);

  static const Color pageBackground = Color(0xFFF8F9FC);
  static const Color card = Color(0xFFFFFFFF);

  // --- Back-compat aliases so existing widgets keep working unchanged ---
  static const Color primary = purple;
  static const Color primaryDark = Color(0xFF554EDB);
  static const Color secondary = blue;
  static const Color accent = orange;

  static const Color background = pageBackground;
  static const Color surface = card;

  static const Color textPrimary = Color(0xFF1E1E2C);
  static const Color textSecondary = Color(0xFF6E7191);

  static const Color success = green;
  static const Color error = Color(0xFFE74C3C);
  static const Color warning = orange;
}

import 'package:flutter/material.dart';

/// Premium color palette for the app-wide theme (visual only - no screen
/// logic changed). Old names (primary/secondary/accent/background/surface)
/// are kept so every existing widget that references AppColors.* keeps
/// compiling; they now point at the new, richer palette's equivalents.
///
/// Updated from the original light pastel shades to richer, slightly
/// darker, premium-looking tones (per design request) - every screen in
/// the app that references these constants picks up the new colors
/// automatically, without any other file needing to change.
class AppColors {
  AppColors._();

  // --- Premium palette ---
  static const Color purple = Color(0xFF5B4CF0);
  static const Color purpleLight = Color(0xFFE1DCFC);

  static const Color orange = Color(0xFFFF5A3D);
  static const Color orangeLight = Color(0xFFFFDDD2);

  static const Color blue = Color(0xFF2563EB);
  static const Color blueLight = Color(0xFFD6E4FE);

  static const Color green = Color(0xFF16A34A);
  static const Color greenLight = Color(0xFFD1F2DC);

  static const Color pageBackground = Color(0xFFF8F9FC);
  static const Color card = Color(0xFFFFFFFF);

  // --- Back-compat aliases so existing widgets keep working unchanged ---
  static const Color primary = purple;
  static const Color primaryDark = Color(0xFF4A3BD8);
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

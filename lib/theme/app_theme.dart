import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFFFAFAFA);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF4F4F6);
  static const border = Color(0xFFE8E8EC);
  static const gold = Color(0xFFC9A84C);
  static const goldLight = Color(0xFFF5EDD6);
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6B6B80);
  static const textHint = Color(0xFFAAAAAF);
  static const shadow = Color(0x14000000);
  static const shadowMd = Color(0x1F000000);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.gold,
        surface: AppColors.surface,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.dmSans(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// Reusable shadow decoration
BoxDecoration cardDecoration({
  Color color = AppColors.surface,
  double radius = 16,
  bool bordered = true,
}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: bordered ? Border.all(color: AppColors.border) : null,
      boxShadow: const [
        BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

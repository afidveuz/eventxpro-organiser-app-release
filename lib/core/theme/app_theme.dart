import 'package:flutter/material.dart';

class AppTheme {
  // Vibrant Kiosk Colors
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceElevated = Color(0xFF21262D);
  static const Color surfaceBorder = Color(0xFF30363D);

  // Status Feedback Colors
  static const Color statusSuccess = Color(0xFF00E676);     // Large Green: Accepted
  static const Color statusSuccessBg = Color(0xFF052E16);
  static const Color statusWarning = Color(0xFFFFB300);     // Amber: Already Checked In
  static const Color statusWarningBg = Color(0xFF3E2800);
  static const Color statusRejected = Color(0xFFFF1744);    // Red: Denied / Expired / Invalid
  static const Color statusRejectedBg = Color(0xFF3B0D11);
  static const Color statusPending = Color(0xFF00E5FF);     // Blue: Queued / Network In Flight
  static const Color statusPendingBg = Color(0xFF00223A);

  // Accent & Neutral
  static const Color accentIndigo = Color(0xFF6366F1);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);

  // EventXPro Signature Brand Theme Colors
  static const Color eventxproBg = Color(0xFF171C26);
  static const Color eventxproNavy = Color(0xFF0C1A52);
  static const Color eventxproAccent = Color(0xFFC10067); // Signature Magenta Pink
  static const Color eventxproCardBg = Color(0xFFFFFFFF);
  static const Color eventxproSuccess = Color(0xFF8DFFBB); // Check-in Green
  static const Color eventxproSuccessDark = Color(0xFF39BD76);
  static const Color eventxproDanger = Color(0xFFFF6767); // Check-out Red
  static const Color eventxproBorder = Color(0x66FFFFFF); // rgba(255, 255, 255, 0.40)
  static const Color eventxproDarkText = Color(0xFF1E1638);

  // Brand Linear Gradient: 135deg (#f43f5e -> #7c3aed)
  static const Color brandGradientStart = Color(0xFFF43F5E); // #f43f5e
  static const Color brandGradientEnd = Color(0xFF7C3AED);   // #7c3aed
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandGradientStart, brandGradientEnd],
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accentIndigo,
        surface: surface,
        error: statusRejected,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      fontFamily: 'Segoe UI',
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

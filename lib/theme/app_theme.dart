import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color cream = Color(0xFFF5F0E8);
  static const Color navy = Color(0xFF1A2355);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGrey = Color(0xFFEEEBE3);
  static const Color green = Color(0xFF2ECC71);
  static const Color red = Color(0xFFE74C3C);
  static const Color blue = Color(0xFF3498DB);
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textGrey = Color(0xFF888888);
  static const Color orange = Color(0xFFE67E22);

  static ThemeData get theme => ThemeData(
        scaffoldBackgroundColor: cream,
        colorScheme: const ColorScheme.light(
          primary: navy,
          secondary: yellow,
          surface: cream,
        ),
        textTheme: GoogleFonts.dmSansTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          elevation: 0,
          iconTheme: IconThemeData(color: textDark),
          titleTextStyle: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        useMaterial3: true,
      );
}

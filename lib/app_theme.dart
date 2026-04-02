import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Paleta de colores — referencia UI_ref.jpg
// ---------------------------------------------------------------------------
class KScanColors {
  KScanColors._();

  static const Color background = Color(0xFFF6F6F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF2F2F2F);
  static const Color ink = Color(0xFF111111);
  static const Color accent = Color(0xFFFFCB74);
  static const Color accentLight = Color(0xFFFFF3DC);
  static const Color muted = Color(0xFF888888);
  static const Color divider = Color(0xFFEEEEEE);

  // Estado de sesión
  static const Color stateRunning = Color(0xFF2F2F2F);
  static const Color statePaused = Color(0xFF5C5C5C);
  static const Color stateStop = Color(0xFFE53935);
}

// ---------------------------------------------------------------------------
// Tema central de la app
// ---------------------------------------------------------------------------
class KScanTheme {
  KScanTheme._();

  static ThemeData get theme {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: KScanColors.ink,
      onPrimary: KScanColors.surface,
      secondary: KScanColors.accent,
      onSecondary: KScanColors.ink,
      primaryContainer: KScanColors.surfaceDark,
      onPrimaryContainer: KScanColors.background,
      secondaryContainer: KScanColors.accentLight,
      onSecondaryContainer: KScanColors.ink,
      surface: KScanColors.surface,
      onSurface: KScanColors.ink,
      surfaceContainerHighest: Color(0xFFEEEEEE),
      onSurfaceVariant: KScanColors.muted,
      error: KScanColors.stateStop,
      onError: KScanColors.surface,
    );

    final base = GoogleFonts.interTextTheme().apply(
      bodyColor: KScanColors.ink,
      displayColor: KScanColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KScanColors.background,
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: KScanColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: KScanColors.ink),
        actionsIconTheme: const IconThemeData(color: KScanColors.ink),
        titleTextStyle: GoogleFonts.inter(
          color: KScanColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: KScanColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KScanColors.divider),
        ),
        margin: const EdgeInsets.only(bottom: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KScanColors.accent,
          foregroundColor: KScanColors.ink,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: KScanColors.accent,
        foregroundColor: KScanColors.ink,
        shape: StadiumBorder(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: KScanColors.accent,
        linearTrackColor: KScanColors.divider,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return KScanColors.ink;
            }
            return KScanColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return KScanColors.surface;
            }
            return KScanColors.ink;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: KScanColors.divider),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: KScanColors.divider),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: KScanColors.surface,
        elevation: 4,
        shadowColor: Colors.black12,
      ),
    );
  }
}

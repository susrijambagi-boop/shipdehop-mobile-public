import 'package:flutter/material.dart';
import 'shipdehop_colors.dart';

class ShipdeHopTheme {
  ShipdeHopTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ShipdeHopColors.background,
      colorScheme: const ColorScheme.light(
        primary: ShipdeHopColors.brandPrimary,
        secondary: ShipdeHopColors.brandDark,
        surface: ShipdeHopColors.surfaceCard,
        error: ShipdeHopColors.error,
        onPrimary: ShipdeHopColors.textOnPrimary,
        onSurface: ShipdeHopColors.textPrimary,
      ),
      fontFamily: null, // Uses default system font (San Francisco on iOS, Roboto on Android)
      appBarTheme: const AppBarTheme(
        backgroundColor: ShipdeHopColors.surfaceCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: ShipdeHopColors.textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ShipdeHopColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: ShipdeHopColors.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: ShipdeHopColors.borderLight, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ShipdeHopColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: ShipdeHopColors.surfaceCard,
        selectedItemColor: ShipdeHopColors.brandPrimary,
        unselectedItemColor: ShipdeHopColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ShipdeHopColors.surfaceCard,
        indicatorColor: ShipdeHopColors.brandPrimaryLight,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: ShipdeHopColors.brandPrimary, size: 24);
          }
          return const IconThemeData(color: ShipdeHopColors.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ShipdeHopColors.brandPrimary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: ShipdeHopColors.textSecondary,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ShipdeHopColors.surfaceSubtle,
        selectedColor: ShipdeHopColors.brandPrimaryLight,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ShipdeHopColors.textSecondary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ShipdeHopColors.brandPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.transparent),
        ),
      ),
    );
  }
}

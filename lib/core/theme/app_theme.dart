import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

abstract final class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.purpleLight,
          secondary: AppColors.pathOrange,
          surface: AppColors.darkSurface,
          error: AppColors.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimaryDark,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.deepBlack,
        textTheme: _buildTextTheme(Brightness.dark),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimaryDark,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.navBarBackground,
          selectedItemColor: AppColors.navBarSelected,
          unselectedItemColor: AppColors.navBarUnselected,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            side: const BorderSide(
              color: AppColors.cellBorder,
              width: 0.5,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.purpleDeep,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, AppSizes.minTouchTarget + 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimaryDark,
            side: const BorderSide(color: AppColors.cellBorder, width: 1.5),
            minimumSize: const Size(double.infinity, AppSizes.minTouchTarget + 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.elevatedSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: const BorderSide(color: AppColors.cellBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: const BorderSide(color: AppColors.cellBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: const BorderSide(color: AppColors.purpleLight),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
          hintStyle: TextStyle(color: AppColors.textTertiaryDark),
          prefixIconColor: AppColors.textSecondaryDark,
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 4,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.cellBorder,
          thickness: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.elevatedSurface,
          contentTextStyle: const TextStyle(color: AppColors.textPrimaryDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSizes.radiusLg),
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.purpleLight;
            }
            return AppColors.textTertiaryDark;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.purpleDeep.withValues(alpha: 0.5);
            }
            return AppColors.cellBackground;
          }),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.textSecondaryDark,
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.elevatedSurface),
          ),
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.purpleDeep,
          secondary: AppColors.coralOrange,
          surface: AppColors.lightSurface,
          error: AppColors.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.lightOnSurface,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.lightBackground,
        textTheme: _buildTextTheme(Brightness.light),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.lightBackground,
          foregroundColor: AppColors.lightOnBackground,
          elevation: 0,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.lightSurface,
          selectedItemColor: AppColors.purpleDeep,
          unselectedItemColor: AppColors.textSecondaryLight,
          type: BottomNavigationBarType.fixed,
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightSurface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.purpleDeep,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, AppSizes.minTouchTarget + 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.purpleDeep,
            side: const BorderSide(color: AppColors.purpleDeep),
            minimumSize: const Size(double.infinity, AppSizes.minTouchTarget + 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: const BorderSide(color: AppColors.lightGridLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: const BorderSide(color: AppColors.purpleDeep),
          ),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 4,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.lightGridLine,
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

  static TextTheme _buildTextTheme(Brightness brightness) {
    final baseColor = brightness == Brightness.dark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final secondaryColor = brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    final base = GoogleFonts.interTextTheme(
      TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    // Apply colors AFTER GoogleFonts to prevent them being stripped
    return base.apply(
      bodyColor: baseColor,
      displayColor: baseColor,
    ).copyWith(
      bodySmall: base.bodySmall?.copyWith(color: secondaryColor),
      labelMedium: base.labelMedium?.copyWith(color: secondaryColor),
    );
  }
}

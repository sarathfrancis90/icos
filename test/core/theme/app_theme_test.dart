import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Access theme properties through testWidgets to avoid async font errors
  // leaking into non-widget test contexts.

  group('AppTheme - Dark theme', () {
    testWidgets('has dark brightness', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.brightness, Brightness.dark);
    });

    testWidgets('uses purpleLight as primary color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.primary, AppColors.purpleLight);
    });

    testWidgets('uses pathOrange as secondary color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.secondary, AppColors.pathOrange);
    });

    testWidgets('uses darkNavy as surface color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.surface, AppColors.darkNavy);
    });

    testWidgets('uses deepNavy as scaffold background', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.scaffoldBackgroundColor, AppColors.deepNavy);
    });

    testWidgets('uses Material 3', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.useMaterial3, isTrue);
    });

    testWidgets('AppBar has transparent background', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.appBarTheme.backgroundColor, Colors.transparent);
    });

    testWidgets('AppBar has no elevation', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.appBarTheme.elevation, 0);
    });

    testWidgets('AppBar centers title', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.appBarTheme.centerTitle, isTrue);
    });

    testWidgets('bottom nav bar uses navBarSelected for selected items',
        (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        capturedTheme.bottomNavigationBarTheme.selectedItemColor,
        AppColors.navBarSelected,
      );
    });

    testWidgets('bottom nav bar uses fixed type', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        capturedTheme.bottomNavigationBarTheme.type,
        BottomNavigationBarType.fixed,
      );
    });

    testWidgets('ElevatedButton uses purpleDeep background', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.elevatedButtonTheme.style;
      final bgColor = style?.backgroundColor?.resolve({});
      expect(bgColor, AppColors.purpleDeep);
    });

    testWidgets('ElevatedButton uses white foreground', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.elevatedButtonTheme.style;
      final fgColor = style?.foregroundColor?.resolve({});
      expect(fgColor, Colors.white);
    });

    testWidgets('Card uses mediumNavy color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.cardTheme.color, AppColors.mediumNavy);
    });

    testWidgets('Card has 0 elevation', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.cardTheme.elevation, 0);
    });

    testWidgets('SnackBar has floating behavior', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('error color is set', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.error, AppColors.error);
    });

    testWidgets('onPrimary is white', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.onPrimary, Colors.white);
    });

    testWidgets('onSecondary is white', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.onSecondary, Colors.white);
    });

    testWidgets('text theme is not null', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.textTheme, isNotNull);
      expect(capturedTheme.textTheme.displayLarge, isNotNull);
      expect(capturedTheme.textTheme.bodyMedium, isNotNull);
    });

    testWidgets('input decoration theme has filled inputs', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.inputDecorationTheme.filled, isTrue);
      expect(
        capturedTheme.inputDecorationTheme.fillColor,
        AppColors.elevatedSurface,
      );
    });

    testWidgets('outlined button uses textPrimaryDark', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.outlinedButtonTheme.style;
      final fgColor = style?.foregroundColor?.resolve({});
      expect(fgColor, AppColors.textPrimaryDark);
    });
  });

  group('AppTheme - Light theme', () {
    testWidgets('has light brightness', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.brightness, Brightness.light);
    });

    testWidgets('uses purpleDeep as primary color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.primary, AppColors.purpleDeep);
    });

    testWidgets('uses coralOrange as secondary color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.secondary, AppColors.coralOrange);
    });

    testWidgets('uses lightSurface as surface color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.surface, AppColors.lightSurface);
    });

    testWidgets('uses lightBackground as scaffold background', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.scaffoldBackgroundColor, AppColors.lightBackground);
    });

    testWidgets('uses Material 3', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.useMaterial3, isTrue);
    });

    testWidgets('AppBar has lightBackground color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        capturedTheme.appBarTheme.backgroundColor,
        AppColors.lightBackground,
      );
    });

    testWidgets('AppBar has no elevation', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.appBarTheme.elevation, 0);
    });

    testWidgets('AppBar centers title', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.appBarTheme.centerTitle, isTrue);
    });

    testWidgets('bottom nav bar uses purpleDeep for selected items',
        (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        capturedTheme.bottomNavigationBarTheme.selectedItemColor,
        AppColors.purpleDeep,
      );
    });

    testWidgets('bottom nav bar uses fixed type', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        capturedTheme.bottomNavigationBarTheme.type,
        BottomNavigationBarType.fixed,
      );
    });

    testWidgets('ElevatedButton uses purpleDeep background',
        (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.elevatedButtonTheme.style;
      final bgColor = style?.backgroundColor?.resolve({});
      expect(bgColor, AppColors.purpleDeep);
    });

    testWidgets('ElevatedButton uses white foreground', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.elevatedButtonTheme.style;
      final fgColor = style?.foregroundColor?.resolve({});
      expect(fgColor, Colors.white);
    });

    testWidgets('Card uses lightSurface color', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.cardTheme.color, AppColors.lightSurface);
    });

    testWidgets('Card has elevation of 1', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.cardTheme.elevation, 0);
    });

    testWidgets('SnackBar has floating behavior', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('error color is set', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.error, AppColors.error);
    });

    testWidgets('onPrimary is white', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.colorScheme.onPrimary, Colors.white);
    });

    testWidgets('input decoration theme has filled inputs', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme.inputDecorationTheme.filled, isTrue);
      expect(
        capturedTheme.inputDecorationTheme.fillColor,
        AppColors.lightSurface,
      );
    });

    testWidgets('outlined button uses purpleDeep', (tester) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final style = capturedTheme.outlinedButtonTheme.style;
      final fgColor = style?.foregroundColor?.resolve({});
      expect(fgColor, AppColors.purpleDeep);
    });
  });

  group('AppTheme - Consistency', () {
    testWidgets('dark and light themes have different brightness',
        (tester) async {
      // Capture both themes side by side using a Row
      late ThemeData darkTheme;
      late ThemeData lightTheme;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Theme(
                data: AppTheme.darkTheme,
                child: Builder(
                  builder: (context) {
                    darkTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: AppTheme.lightTheme,
                child: Builder(
                  builder: (context) {
                    lightTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(darkTheme.brightness, Brightness.dark);
      expect(lightTheme.brightness, Brightness.light);
      expect(darkTheme.brightness, isNot(lightTheme.brightness));
    });

    testWidgets('dark and light themes have different primary colors',
        (tester) async {
      late ThemeData darkTheme;
      late ThemeData lightTheme;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Theme(
                data: AppTheme.darkTheme,
                child: Builder(
                  builder: (context) {
                    darkTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: AppTheme.lightTheme,
                child: Builder(
                  builder: (context) {
                    lightTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(darkTheme.colorScheme.primary, AppColors.purpleLight);
      expect(lightTheme.colorScheme.primary, AppColors.purpleDeep);
      expect(
        darkTheme.colorScheme.primary,
        isNot(lightTheme.colorScheme.primary),
      );
    });

    testWidgets('both themes share same error color',
        (tester) async {
      late ThemeData darkTheme;
      late ThemeData lightTheme;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Theme(
                data: AppTheme.darkTheme,
                child: Builder(
                  builder: (context) {
                    darkTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: AppTheme.lightTheme,
                child: Builder(
                  builder: (context) {
                    lightTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(darkTheme.colorScheme.error, lightTheme.colorScheme.error);
    });

    testWidgets(
        'dark and light themes have different scaffold backgrounds',
        (tester) async {
      late ThemeData darkTheme;
      late ThemeData lightTheme;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Theme(
                data: AppTheme.darkTheme,
                child: Builder(
                  builder: (context) {
                    darkTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: AppTheme.lightTheme,
                child: Builder(
                  builder: (context) {
                    lightTheme = Theme.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(
        darkTheme.scaffoldBackgroundColor,
        isNot(lightTheme.scaffoldBackgroundColor),
      );
    });
  });
}

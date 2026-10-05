import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icos/core/theme/app_theme.dart';

/// google_fonts file-name suffix for each weight (see its README).
const _weightNames = <int, String>{
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same switch main() flips: any font that is not bundled must fail loudly
  // here instead of being fetched from fonts.gstatic.com.
  GoogleFonts.config.allowRuntimeFetching = false;

  Iterable<TextStyle> stylesOf(TextTheme t) => [
    t.displayLarge,
    t.displayMedium,
    t.displaySmall,
    t.headlineLarge,
    t.headlineMedium,
    t.headlineSmall,
    t.titleLarge,
    t.titleMedium,
    t.titleSmall,
    t.bodyLarge,
    t.bodyMedium,
    t.bodySmall,
    t.labelLarge,
    t.labelMedium,
    t.labelSmall,
  ].whereType<TextStyle>();

  for (final entry in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
      'the ${entry.key} theme renders text with runtime fetching off and '
      'no font-load error',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: Column(
                children: [
                  for (final style in stylesOf(entry.value.textTheme))
                    Text('Icos', style: style),
                ],
              ),
            ),
          ),
        );
        // Throws the underlying exception if any variant is not bundled.
        await GoogleFonts.pendingFonts();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('every weight the theme asks for is a bundled, declared asset', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    final weights = <int>{
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme])
        for (final style in stylesOf(theme.textTheme))
          (style.fontWeight ?? FontWeight.w400).value,
    };
    expect(weights, isNotEmpty);
    for (final weight in weights) {
      final name = _weightNames[weight];
      expect(name, isNotNull, reason: 'no file-name mapping for w$weight');
      expect(
        assets.any((a) => a.endsWith('google_fonts/Inter-$name.ttf')),
        isTrue,
        reason: 'Inter-$name.ttf (w$weight) is not a declared asset',
      );
    }
    expect(
      assets.any((a) => a.endsWith('google_fonts/OFL.txt')),
      isTrue,
      reason: 'the OFL license text ships with the fonts',
    );
  });

  test('lib/ only uses the Inter family from GoogleFonts', () {
    final used = <String>{};
    final pattern = RegExp(r'GoogleFonts\.([a-zA-Z]+)\(');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final m in pattern.allMatches(file.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    // Anything new needs its own files under assets/google_fonts/.
    expect(used, {'interTextTheme'});
  });

  test('main() turns runtime fetching off', () {
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('GoogleFonts.config.allowRuntimeFetching = false'),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/theme_provider.dart';

/// System / Dark / Light selector shown in Profile settings.
class ThemeModeDropdown extends ConsumerWidget {
  const ThemeModeDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    return DropdownButton<ThemeMode>(
      value: themeMode,
      underline: const SizedBox.shrink(),
      // The menu text follows the theme, so the menu surface must too.
      dropdownColor: Theme.of(context).brightness == Brightness.dark
          ? context.palette.elevated
          : AppColors.lightSurface,
      onChanged: (mode) {
        if (mode != null) {
          ref.read(themeModeNotifierProvider.notifier).setThemeMode(mode);
        }
      },
      items: const [
        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
      ],
    );
  }
}

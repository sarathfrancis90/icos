import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../providers/profile_provider.dart';

/// A bottom sheet widget for selecting colorblind mode.
class ColorblindSelector extends ConsumerWidget {
  const ColorblindSelector({
    super.key,
    required this.currentMode,
  });

  final String currentMode;

  static const _modes = [
    _ColorblindOption(
      key: 'none',
      label: 'None',
      description: 'Default colors',
      pathColor: AppColors.pathFill,
      waypointColor: AppColors.waypointFill,
    ),
    _ColorblindOption(
      key: 'deuteranopia',
      label: 'Deuteranopia',
      description: 'Green-blind friendly',
      pathColor: AppColors.deuteranopiaPath,
      waypointColor: AppColors.deuteranopiaWaypoint,
    ),
    _ColorblindOption(
      key: 'protanopia',
      label: 'Protanopia',
      description: 'Red-blind friendly',
      pathColor: AppColors.protanopiaPath,
      waypointColor: AppColors.protanopiaWaypoint,
    ),
    _ColorblindOption(
      key: 'tritanopia',
      label: 'Tritanopia',
      description: 'Blue-blind friendly',
      pathColor: AppColors.tritanopiaPath,
      waypointColor: AppColors.tritanopiaWaypoint,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              child: Text(
                'Colorblind Mode',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              child: Text(
                'Choose a color palette that works best for you',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            ...List.generate(_modes.length, (index) {
              final option = _modes[index];
              final isSelected = option.key == currentMode;

              return _ColorblindOptionTile(
                option: option,
                isSelected: isSelected,
                onTap: () => _selectMode(context, ref, option.key),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMode(
    BuildContext context,
    WidgetRef ref,
    String mode,
  ) async {
    if (mode == currentMode) {
      Navigator.of(context).pop();
      return;
    }

    final result = await ref
        .read(profileNotifierProvider.notifier)
        .updateColorblindMode(mode);

    if (!context.mounted) return;

    switch (result) {
      case Success():
        Navigator.of(context).pop();
      case Failure(error: final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
    }
  }
}

class _ColorblindOption {
  const _ColorblindOption({
    required this.key,
    required this.label,
    required this.description,
    required this.pathColor,
    required this.waypointColor,
  });

  final String key;
  final String label;
  final String description;
  final Color pathColor;
  final Color waypointColor;
}

class _ColorblindOptionTile extends StatelessWidget {
  const _ColorblindOptionTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _ColorblindOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSizes.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.sm,
        ),
        child: Row(
          children: [
            // Color preview swatches
            Row(
              children: [
                _ColorSwatch(
                  color: option.pathColor,
                  label: 'P',
                ),
                const SizedBox(width: AppSizes.xs),
                _ColorSwatch(
                  color: option.waypointColor,
                  label: 'W',
                ),
              ],
            ),
            const SizedBox(width: AppSizes.md),
            // Label and description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    option.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // Selection indicator
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../puzzle/providers/tap_to_draw_provider.dart';

/// Settings switch for the tap-to-draw input mode.
class TapToDrawTile extends ConsumerWidget {
  const TapToDrawTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      secondary: const Icon(Icons.touch_app_rounded),
      title: const Text(AppStrings.tapToDrawTitle),
      subtitle: const Text(AppStrings.tapToDrawSubtitle),
      value: ref.watch(tapToDrawProvider),
      onChanged: (v) => ref.read(tapToDrawProvider.notifier).set(v),
    );
  }
}

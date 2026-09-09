import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../profile/providers/profile_provider.dart';

part 'colorblind_mode_provider.g.dart';

enum ColorblindMode {
  none,
  deuteranopia,
  protanopia,
  tritanopia;

  static ColorblindMode parse(String? value) {
    for (final m in ColorblindMode.values) {
      if (m.name == value) return m;
    }
    return ColorblindMode.none;
  }

  bool get isActive => this != ColorblindMode.none;
}

/// Active colorblind palette. Reads [StorageService.colorblindMode] and
/// follows the signed-in profile's setting when it loads / changes.
@Riverpod(keepAlive: true)
class ColorblindModeNotifier extends _$ColorblindModeNotifier {
  @override
  ColorblindMode build() {
    ref.listen<String?>(
      profileNotifierProvider.select((p) => p.valueOrNull?.colorblindMode),
      (_, mode) {
        if (mode == null) return;
        final parsed = ColorblindMode.parse(mode);
        if (parsed != state) {
          state = parsed;
          StorageService.setColorblindMode(parsed.name);
        }
      },
    );
    return ColorblindMode.parse(StorageService.colorblindMode);
  }

  Future<void> setMode(ColorblindMode mode) async {
    state = mode;
    await StorageService.setColorblindMode(mode.name);
  }
}

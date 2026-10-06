import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';

part 'tap_to_draw_provider.g.dart';

/// "Tap to draw" accessibility mode: device-level, default off. Dragging keeps
/// working either way; the mode changes the guidance and the screen-reader
/// hints.
@Riverpod(keepAlive: true)
class TapToDraw extends _$TapToDraw {
  @override
  bool build() => StorageService.tapToDraw;

  Future<void> set(bool value) async {
    state = value;
    await StorageService.setTapToDraw(value);
  }
}

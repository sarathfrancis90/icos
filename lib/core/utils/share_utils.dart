import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Shares one file through the OS share sheet. Injectable so logic that ends
/// in a share can be tested without a platform.
typedef FileSharer =
    Future<void> Function({
      required XFile file,
      String? subject,
      String? text,
      Rect? origin,
    });

/// Default [FileSharer]: the system share sheet via share_plus.
Future<void> platformFileSharer({
  required XFile file,
  String? subject,
  String? text,
  Rect? origin,
}) async {
  await Share.shareXFiles(
    [file],
    subject: subject,
    text: text,
    sharePositionOrigin: origin,
  );
}

/// The on-screen rect the share sheet should anchor to.
///
/// iOS now requires a non-empty `sharePositionOrigin` inside the view for
/// every share (not just on iPad, where it is the popover anchor), and the
/// share fails with an error without one. This is the render box of
/// [context] when it is laid out, otherwise a small rect at the centre of the
/// screen.
Rect sharePositionOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

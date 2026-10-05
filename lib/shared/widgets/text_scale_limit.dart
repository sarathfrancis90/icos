import 'package:flutter/widgets.dart';

/// Caps the text scale at [maxScale] for everything below it.
///
/// Layouts are verified to 200% (the project's Dynamic Type requirement).
/// iOS accessibility sizes go well beyond that (Flutter receives them as a
/// scale of up to about 3.1), so larger system sizes are clamped to 200%
/// rather than letting screens break.
class TextScaleLimit extends StatelessWidget {
  const TextScaleLimit({
    required this.child,
    this.maxScale = maxTextScale,
    super.key,
  });

  /// The largest text scale the app lays out for.
  static const double maxTextScale = 2.0;

  final double maxScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxScale,
      child: child,
    );
  }
}

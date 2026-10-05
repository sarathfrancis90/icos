import 'package:flutter/widgets.dart';

/// The user's effective text scale (1.0 = default size).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16;

/// True from about 130% up: rows that sit side by side at normal size should
/// stack vertically so each piece keeps enough width to stay readable.
bool isLargeText(BuildContext context) => textScaleOf(context) > 1.3;

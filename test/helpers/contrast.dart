import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative luminance of an opaque sRGB colour.
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Paints [fg] over [bg] (both may be translucent; [bg] is treated as
/// sitting on black when it is not opaque, so pass an opaque base).
Color compositeOver(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

/// WCAG contrast ratio (1..21) of [fg] on [bg]. A translucent [fg] is first
/// composited over [bg].
double contrastRatio(Color fg, Color bg) {
  final opaqueBg = bg.a < 1 ? compositeOver(bg, const Color(0xFF000000)) : bg;
  final shown = fg.a < 1 ? compositeOver(fg, opaqueBg) : fg;
  final l1 = relativeLuminance(shown);
  final l2 = relativeLuminance(opaqueBg);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// The colour [finder]'s (single) Text widget is actually drawn with, after
/// merging with the ambient DefaultTextStyle as Text itself does.
Color resolvedTextColor(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final text = element.widget as Text;
  return _effectiveStyle(element, text).color ?? const Color(0xFF000000);
}

TextStyle _effectiveStyle(Element element, Text text) {
  var style = text.style;
  final ambient = DefaultTextStyle.of(element);
  if (style == null || style.inherit) {
    style = ambient.style.merge(style);
  }
  return style;
}

/// The colour painted behind [element]: the nearest opaque ancestor fill,
/// with translucent fills composited over what lies beneath them, down to
/// [fallback] (the surface the screen is known to sit on).
Color backgroundBehind(Element element, {required Color fallback}) {
  final layers = <Color>[];
  element.visitAncestorElements((a) {
    final w = a.widget;
    Color? fill;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final d = w.decoration as BoxDecoration;
      fill = d.color ?? (d.gradient?.colors.first);
    } else if (w is ColoredBox) {
      fill = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      fill = w.color;
    }
    if (fill != null && fill.a > 0) {
      layers.add(fill);
      if (fill.a >= 1) return false;
    }
    return true;
  });
  var result = fallback;
  for (final layer in layers.reversed) {
    result = compositeOver(layer, result);
  }
  return result;
}

/// Contrast of the text found by [finder] against what is painted behind it.
double textContrast(
  WidgetTester tester,
  Finder finder, {
  required Color fallbackBackground,
}) {
  final fg = resolvedTextColor(tester, finder);
  final bg = backgroundBehind(
    tester.element(finder),
    fallback: fallbackBackground,
  );
  return contrastRatio(fg, bg);
}

/// Minimum ratio for a Text: 3:1 for large text (>= 24px, or >= 18.66px
/// bold), otherwise 4.5:1.
double requiredRatio(Text text, TextStyle style) {
  final size = style.fontSize ?? 14;
  final bold = (style.fontWeight?.index ?? 3) >= FontWeight.w700.index;
  return (size >= 24 || (bold && size >= 18.66)) ? 3.0 : 4.5;
}

/// Checks every Text under [scope] (default: the whole tree) and returns a
/// description of each failure; empty means the surface passes.
List<String> contrastFailures(
  WidgetTester tester, {
  required Color fallbackBackground,
  Finder? scope,
}) {
  final texts = scope == null
      ? find.byType(Text)
      : find.descendant(of: scope, matching: find.byType(Text));
  final failures = <String>[];
  for (final element in texts.evaluate()) {
    final text = element.widget as Text;
    final label = text.data ?? text.textSpan?.toPlainText() ?? '';
    if (label.trim().isEmpty) continue;
    final style = _effectiveStyle(element, text);
    final fg = style.color ?? const Color(0xFF000000);
    final bg = backgroundBehind(element, fallback: fallbackBackground);
    final ratio = contrastRatio(fg, bg);
    final need = requiredRatio(text, style);
    if (ratio < need) {
      failures.add(
        '"$label": ${ratio.toStringAsFixed(2)}:1 < $need:1 '
        '(fg $fg on $bg)',
      );
    }
  }
  return failures;
}

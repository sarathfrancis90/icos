import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

void main() {
  test('contrastRatio matches the WCAG reference values', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.001),
    );
    expect(
      contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
      closeTo(1, 0.001),
    );
    // #767676 on white is the well-known 4.54:1 AA threshold grey.
    expect(
      contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
      closeTo(4.54, 0.01),
    );
  });
}

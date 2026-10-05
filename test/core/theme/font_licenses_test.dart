import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/theme/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the Inter OFL text is in the license registry', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final inter = entries.where((e) => e.packages.contains('Inter'));
    expect(inter, hasLength(1));
    final text = inter.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE'));
    expect(text, contains('Inter Project Authors'));
  });
}

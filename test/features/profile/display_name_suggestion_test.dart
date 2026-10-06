import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/profile/domain/display_name_suggestion.dart';

void main() {
  group('tidyEmailLocalPart', () {
    test('splits on separators and title-cases', () {
      expect(tidyEmailLocalPart('ada.lovelace@example.com'), 'Ada Lovelace');
      expect(
        tidyEmailLocalPart('GRACE_hopper-x+y@example.com'),
        'Grace Hopper X Y',
      );
      expect(tidyEmailLocalPart('a..b@example.com'), 'A B');
    });

    test('Apple relay addresses give nothing', () {
      expect(tidyEmailLocalPart('k3x9q2abc@privaterelay.appleid.com'), isNull);
      expect(tidyEmailLocalPart('k3x9q2abc@PrivateRelay.AppleID.com'), isNull);
    });

    test('missing or malformed email gives nothing', () {
      expect(tidyEmailLocalPart(null), isNull);
      expect(tidyEmailLocalPart(''), isNull);
      expect(tidyEmailLocalPart('@example.com'), isNull);
      expect(tidyEmailLocalPart('..@example.com'), isNull);
    });

    test('cap does not split an emoji at the boundary', () {
      final out = tidyEmailLocalPart('${'a' * 29}\u{1F600}b@example.com')!;
      expect(out.characters.length, 30);
      expect(out.endsWith('\u{1F600}'), isTrue);
      final name = suggestDisplayName(
        meta: {'full_name': '${'a' * 29}\u{1F468}\u200D\u{1F469}x'},
        email: null,
      );
      expect(name.characters.length, 30);
    });

    test('capped at 30 characters', () {
      final out = tidyEmailLocalPart('${'a' * 40}@example.com')!;
      expect(out.length, 30);
    });
  });

  group('suggestDisplayName', () {
    test('provider name wins, in the server order', () {
      expect(
        suggestDisplayName(
          meta: {'full_name': ' Grace Hopper ', 'name': 'X'},
          email: 'ada@example.com',
        ),
        'Grace Hopper',
      );
      expect(suggestDisplayName(meta: {'name': 'Nm'}, email: null), 'Nm');
      expect(
        suggestDisplayName(
          meta: {'given_name': 'Grace', 'family_name': 'Hopper'},
          email: null,
        ),
        'Grace Hopper',
      );
      expect(
        suggestDisplayName(meta: {'given_name': 'Grace'}, email: null),
        'Grace',
      );
      expect(
        suggestDisplayName(meta: {'preferred_username': 'gh'}, email: null),
        'gh',
      );
    });

    test('falls back to the tidied email local part', () {
      expect(
        suggestDisplayName(meta: {}, email: 'ada.lovelace@example.com'),
        'Ada Lovelace',
      );
    });

    test('relay email without a name gives empty', () {
      expect(
        suggestDisplayName(meta: null, email: 'zz9@privaterelay.appleid.com'),
        '',
      );
    });

    test('relay email with a name gives the name', () {
      expect(
        suggestDisplayName(
          meta: {'full_name': 'Ada'},
          email: 'zz9@privaterelay.appleid.com',
        ),
        'Ada',
      );
    });
  });
}

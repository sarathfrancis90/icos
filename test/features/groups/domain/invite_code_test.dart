import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/groups/domain/group_name_validator.dart';
import 'package:icos/features/groups/domain/invite_code.dart';

void main() {
  group('InviteCode', () {
    test('normalize upper-cases and strips whitespace/dashes', () {
      expect(InviteCode.normalize(' ab-c 12d '), 'ABC12D');
    });

    test('accepts exactly six uppercase alphanumerics', () {
      expect(InviteCode.isValid('ABC123'), isTrue);
      expect(InviteCode.isValid('abc123'), isTrue, reason: 'normalised');
      expect(InviteCode.isValid('ZZZZZZ'), isTrue);
      expect(InviteCode.isValid('000000'), isTrue);
    });

    test('rejects wrong length or non-alphanumerics', () {
      expect(InviteCode.isValid('ABC12'), isFalse);
      expect(InviteCode.isValid('ABC1234'), isFalse);
      expect(InviteCode.isValid('ABC12!'), isFalse);
      expect(InviteCode.isValid(''), isFalse);
      expect(InviteCode.isValid('ÄBC123'), isFalse);
    });

    test('validate returns messages', () {
      expect(InviteCode.validate(null), isNotNull);
      expect(InviteCode.validate('   '), isNotNull);
      expect(InviteCode.validate('ABC'), contains('6-character'));
      expect(InviteCode.validate('abc123'), isNull);
    });

    test('joinLink builds the public deep link', () {
      expect(InviteCode.joinLink('abc123'), 'https://icos.sarathfrancis.work/join/ABC123');
    });
  });

  group('GroupNameValidator', () {
    test('requires 2–30 characters', () {
      expect(GroupNameValidator.validate(null), isNotNull);
      expect(GroupNameValidator.validate(''), isNotNull);
      expect(GroupNameValidator.validate('a'), 'Must be at least 2 characters');
      expect(GroupNameValidator.validate('ab'), isNull);
      expect(GroupNameValidator.validate('x' * 30), isNull);
      expect(GroupNameValidator.validate('x' * 31), 'Max 30 characters');
    });

    test('sanitizes invisible characters and whitespace', () {
      expect(
        GroupNameValidator.sanitize('  Sun\u200Bday   Solvers  '),
        'Sunday Solvers',
      );
      expect(GroupNameValidator.validate('\u200B\u200B'), isNotNull);
    });

    test('blocks profanity including leetspeak', () {
      expect(GroupNameValidator.validate('Nice Group'), isNull);
      expect(GroupNameValidator.validate('sh1t crew'), 'This name is not allowed');
      expect(GroupNameValidator.validate('the admins'), 'This name is not allowed');
      expect(GroupNameValidator.containsProfanity('F.U.C.K'), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/profile/domain/account_deletion_copy.dart';

void main() {
  test('guest copy promises nothing recoverable and no grace period', () {
    final body = AccountDeletionCopy.dialogBody(isGuest: true);
    expect(body, contains('cannot be recovered'));
    expect(body, isNot(contains('30')));
    expect(body.toLowerCase(), isNot(contains('sign back in')));
    final done = AccountDeletionCopy.doneMessage(isGuest: true);
    expect(done, isNot(contains('30')));
    expect(done.toLowerCase(), isNot(contains('sign in')));
  });

  test('member copy keeps the 30-day sign-in-to-cancel promise', () {
    expect(AccountDeletionCopy.dialogBody(isGuest: false), contains('30 days'));
    expect(
      AccountDeletionCopy.doneMessage(isGuest: false),
      contains('Sign in within 30 days'),
    );
  });
}

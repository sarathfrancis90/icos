import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';

void main() {
  group('AuthStrategy.forOAuth', () {
    test('anonymous users always link (web flow) regardless of platform', () {
      for (final platform in AuthPlatform.values) {
        for (final provider in OAuthKind.values) {
          for (final hasIds in [true, false]) {
            expect(
              AuthStrategy.forOAuth(
                isAnonymous: true,
                platform: platform,
                provider: provider,
                hasClientIds: hasIds,
              ),
              OAuthMethod.linkIdentityWeb,
              reason: '$platform/$provider/ids=$hasIds',
            );
          }
        }
      }
    });

    test('non-anonymous Google uses native id-token when ids configured', () {
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.android,
          provider: OAuthKind.google,
          hasClientIds: true,
        ),
        OAuthMethod.nativeIdToken,
      );
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.ios,
          provider: OAuthKind.google,
          hasClientIds: true,
        ),
        OAuthMethod.nativeIdToken,
      );
    });

    test('non-anonymous Google falls back to web without ids', () {
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.android,
          provider: OAuthKind.google,
          hasClientIds: false,
        ),
        OAuthMethod.webOAuth,
      );
    });

    test('Apple is native on iOS only', () {
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.ios,
          provider: OAuthKind.apple,
          hasClientIds: false,
        ),
        OAuthMethod.nativeIdToken,
      );
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.android,
          provider: OAuthKind.apple,
          hasClientIds: true,
        ),
        OAuthMethod.webOAuth,
      );
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.other,
          provider: OAuthKind.apple,
          hasClientIds: true,
        ),
        OAuthMethod.webOAuth,
      );
    });

    test('unknown platform never uses native', () {
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.other,
          provider: OAuthKind.google,
          hasClientIds: true,
        ),
        OAuthMethod.webOAuth,
      );
    });
  });

  group('AuthStrategy.forEmail', () {
    test('guest creating an account converts via updateUser', () {
      expect(
        AuthStrategy.forEmail(isAnonymous: true, isSignUp: true),
        EmailMethod.updateUser,
      );
    });

    test('fresh sign-up uses signUp', () {
      expect(
        AuthStrategy.forEmail(isAnonymous: false, isSignUp: true),
        EmailMethod.signUp,
      );
    });

    test('sign-in always uses password flow', () {
      expect(
        AuthStrategy.forEmail(isAnonymous: true, isSignUp: false),
        EmailMethod.signInWithPassword,
      );
      expect(
        AuthStrategy.forEmail(isAnonymous: false, isSignUp: false),
        EmailMethod.signInWithPassword,
      );
    });
  });

  group('AuthStrategy.googleClientIdsConfigured', () {
    test('android needs only the web client id', () {
      expect(
        AuthStrategy.googleClientIdsConfigured(
          platform: AuthPlatform.android,
          webClientId: 'web',
          iosClientId: null,
        ),
        isTrue,
      );
      expect(
        AuthStrategy.googleClientIdsConfigured(
          platform: AuthPlatform.android,
          webClientId: '  ',
          iosClientId: 'ios',
        ),
        isFalse,
      );
    });

    test('ios needs both ids', () {
      expect(
        AuthStrategy.googleClientIdsConfigured(
          platform: AuthPlatform.ios,
          webClientId: 'web',
          iosClientId: 'ios',
        ),
        isTrue,
      );
      expect(
        AuthStrategy.googleClientIdsConfigured(
          platform: AuthPlatform.ios,
          webClientId: 'web',
          iosClientId: null,
        ),
        isFalse,
      );
    });

    test('other platforms are never configured', () {
      expect(
        AuthStrategy.googleClientIdsConfigured(
          platform: AuthPlatform.other,
          webClientId: 'web',
          iosClientId: 'ios',
        ),
        isFalse,
      );
    });
  });

  group('AuthStrategy.showAppleButton', () {
    test('shown on iOS, hidden on Android unless web allowed', () {
      expect(AuthStrategy.showAppleButton(AuthPlatform.ios), isTrue);
      expect(AuthStrategy.showAppleButton(AuthPlatform.android), isFalse);
      expect(
        AuthStrategy.showAppleButton(
          AuthPlatform.android,
          allowWebOnAndroid: true,
        ),
        isTrue,
      );
      expect(AuthStrategy.showAppleButton(AuthPlatform.other), isFalse);
    });
  });

  group('AuthStrategy.isIdentityAlreadyExists', () {
    test('recognises codes', () {
      expect(
        AuthStrategy.isIdentityAlreadyExists(code: 'identity_already_exists'),
        isTrue,
      );
      expect(AuthStrategy.isIdentityAlreadyExists(code: 'email_exists'), isTrue);
      expect(
        AuthStrategy.isIdentityAlreadyExists(code: 'user_already_exists'),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(code: 'invalid_credentials'),
        isFalse,
      );
    });

    test('recognises messages', () {
      expect(
        AuthStrategy.isIdentityAlreadyExists(
          message: 'Identity is already linked to another user',
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(
          message: 'A user with this email address has already been registered',
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(message: 'User already registered'),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(message: 'Invalid login'),
        isFalse,
      );
      expect(AuthStrategy.isIdentityAlreadyExists(), isFalse);
    });
  });

  group('AuthStrategy.needsEmailConfirmation', () {
    test('pending new_email requires confirmation', () {
      expect(
        AuthStrategy.needsEmailConfirmation(
          email: null,
          newEmail: 'a@b.c',
          emailConfirmedAt: null,
        ),
        isTrue,
      );
    });

    test('email set but not confirmed requires confirmation', () {
      expect(
        AuthStrategy.needsEmailConfirmation(
          email: 'a@b.c',
          newEmail: null,
          emailConfirmedAt: null,
        ),
        isTrue,
      );
    });

    test('confirmed email does not', () {
      expect(
        AuthStrategy.needsEmailConfirmation(
          email: 'a@b.c',
          newEmail: null,
          emailConfirmedAt: '2026-01-01T00:00:00Z',
        ),
        isFalse,
      );
    });

    test('no email at all does not', () {
      expect(
        AuthStrategy.needsEmailConfirmation(
          email: null,
          newEmail: null,
          emailConfirmedAt: null,
        ),
        isFalse,
      );
    });
  });

  group('AuthStrategy.friendlyMessage', () {
    test('maps known errors', () {
      expect(
        AuthStrategy.friendlyMessage('Invalid login credentials'),
        'Invalid email or password. Please try again.',
      );
      expect(
        AuthStrategy.friendlyMessage('User already registered'),
        'An account with this email already exists.',
      );
      expect(
        AuthStrategy.friendlyMessage('Email not confirmed'),
        'Please check your email to confirm your account.',
      );
      expect(
        AuthStrategy.friendlyMessage('Rate limit exceeded'),
        'Too many attempts. Please wait a moment.',
      );
      expect(
        AuthStrategy.friendlyMessage('SocketException: Failed host lookup'),
        'No internet connection. Please try again.',
      );
    });

    test('falls back to generic copy', () {
      expect(
        AuthStrategy.friendlyMessage('weird'),
        'Something went wrong. Please try again.',
      );
    });
  });

  test('redirect uri matches the registered scheme', () {
    expect(kAuthRedirectUri, 'io.supabase.icos://login-callback');
  });
}

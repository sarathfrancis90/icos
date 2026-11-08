import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/backend/backend_config.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';

void main() {
  group('AuthStrategy.forOAuth', () {
    test('anonymous users always link (same user id) on every platform', () {
      for (final platform in AuthPlatform.values) {
        for (final provider in OAuthKind.values) {
          for (final hasIds in [true, false]) {
            final method = AuthStrategy.forOAuth(
              isAnonymous: true,
              platform: platform,
              provider: provider,
              hasClientIds: hasIds,
            );
            expect(method.links, isTrue, reason: '$platform/$provider/$hasIds');
            final native = AuthStrategy.nativeAvailable(
              platform: platform,
              provider: provider,
              hasClientIds: hasIds,
            );
            expect(
              method,
              native ? OAuthMethod.linkNativeIdToken : OAuthMethod.linkWeb,
              reason: '$platform/$provider/ids=$hasIds',
            );
          }
        }
      }
    });

    test('the provider table: native everywhere but Apple on Android', () {
      OAuthMethod guest(AuthPlatform p, OAuthKind k) => AuthStrategy.forOAuth(
        isAnonymous: true,
        platform: p,
        provider: k,
        hasClientIds: true,
      );
      expect(
        guest(AuthPlatform.ios, OAuthKind.google),
        OAuthMethod.linkNativeIdToken,
      );
      expect(
        guest(AuthPlatform.ios, OAuthKind.apple),
        OAuthMethod.linkNativeIdToken,
      );
      expect(
        guest(AuthPlatform.android, OAuthKind.google),
        OAuthMethod.linkNativeIdToken,
      );
      expect(guest(AuthPlatform.android, OAuthKind.apple), OAuthMethod.linkWeb);
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
    test('guest creating an account is upgraded in place', () {
      expect(
        AuthStrategy.forEmail(isAnonymous: true, isSignUp: true),
        EmailMethod.upgradeGuest,
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
    test('shown on iOS and Android, hidden elsewhere', () {
      expect(AuthStrategy.showAppleButton(AuthPlatform.ios), isTrue);
      expect(AuthStrategy.showAppleButton(AuthPlatform.android), isTrue);
      expect(AuthStrategy.showAppleButton(AuthPlatform.other), isFalse);
    });
  });

  group('AuthStrategy.forOAuth Apple on Android', () {
    test('guest links through the web flow', () {
      expect(
        AuthStrategy.forOAuth(
          isAnonymous: true,
          platform: AuthPlatform.android,
          provider: OAuthKind.apple,
          hasClientIds: true,
        ),
        OAuthMethod.linkWeb,
      );
    });

    test('signed-out or non-anonymous uses web OAuth, never native', () {
      for (final hasIds in [true, false]) {
        final method = AuthStrategy.forOAuth(
          isAnonymous: false,
          platform: AuthPlatform.android,
          provider: OAuthKind.apple,
          hasClientIds: hasIds,
        );
        expect(method, OAuthMethod.webOAuth);
        expect(method, isNot(OAuthMethod.nativeIdToken));
      }
      expect(
        AuthStrategy.nativeAvailable(
          platform: AuthPlatform.android,
          provider: OAuthKind.apple,
          hasClientIds: true,
        ),
        isFalse,
      );
    });
  });

  group('AuthStrategy.isIdentityAlreadyExists', () {
    test('recognises codes', () {
      expect(
        AuthStrategy.isIdentityAlreadyExists(
          code: 'ACCOUNT_ALREADY_LINKED_TO_DIFFERENT_USER',
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(code: 'EMAIL_EXISTS'),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(
          code: 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL',
        ),
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
          message: 'Account already linked to a different user',
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
        AuthStrategy.isIdentityAlreadyExists(
          message: 'User already registered',
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isIdentityAlreadyExists(message: 'Invalid login'),
        isFalse,
      );
      expect(AuthStrategy.isIdentityAlreadyExists(), isFalse);
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
        AuthStrategy.friendlyMessage('Email not verified'),
        'Please check your email to confirm your account.',
      );
      expect(
        AuthStrategy.friendlyMessage('Invalid email or password'),
        'Invalid email or password. Please try again.',
      );
      expect(
        AuthStrategy.friendlyMessage('Password too short'),
        'Please choose a stronger password (at least 6 characters).',
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

    test('friendlyError maps AppError variants', () {
      expect(
        AuthStrategy.friendlyError(const AppError.network('x')),
        'No internet connection. Please try again.',
      );
      expect(
        AuthStrategy.friendlyError(const AppError.conflict('x')),
        'An account with this email already exists.',
      );
      expect(
        AuthStrategy.friendlyError(const AppError.rateLimit('x')),
        'Too many attempts. Please wait a moment.',
      );
      expect(
        AuthStrategy.friendlyError(
          const AppError.auth('boom https://x.test/a?state=SECRET'),
        ),
        'Something went wrong. Please try again.',
      );
    });

    test('falls back to generic copy', () {
      expect(
        AuthStrategy.friendlyMessage('weird'),
        'Something went wrong. Please try again.',
      );
    });
  });

  test('web OAuth redirect is the AuthClient callback (io.icos)', () {
    expect(kOAuthRedirectUri, 'io.icos://oauth-callback');
    expect(kOAuthRedirectUri, kOAuthCallbackUrl);
    expect(Uri.parse(kOAuthRedirectUri).scheme, kOAuthCallbackScheme);
  });

  test('redactUrls keeps host and path only', () {
    final out = AuthStrategy.redactUrls(
      'failed https://fn.example.test/auth/sign-in/social?provider=google'
      '&code_challenge=SECRET&state=XYZ now',
    );
    expect(out, 'failed fn.example.test/auth/sign-in/social now');
    expect(out, isNot(contains('SECRET')));
  });
}

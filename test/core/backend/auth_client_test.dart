import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/backend/auth_client.dart';
import 'package:icos/core/backend/auth_event.dart';
import 'package:icos/core/backend/backend_config.dart';
import 'package:icos/core/backend/token_store.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';

import 'backend_test_helpers.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

void main() {
  late InMemoryTokenStore store;
  late List<http.Request> requests;
  final now = DateTime.utc(2026, 11, 8, 12);

  setUp(() {
    store = InMemoryTokenStore();
    requests = [];
  });

  AuthClient client(
    Future<http.Response> Function(http.Request) handler, {
    WebAuthenticator? web,
  }) => AuthClient(
    MockClient((req) {
      requests.add(req);
      return handler(req);
    }),
    testConfig,
    store,
    webAuthenticator: web,
    clock: () => now,
  );

  test('anonymous sign-in stores set-auth-token and emits signedIn', () async {
    final auth = client(
      (req) async => _json(
        {'token': 'body-token', 'user': userJson(anonymous: true)},
        200,
        {'set-auth-token': 'header-token'},
      ),
    );
    final events = <AuthEvent>[];
    auth.events.listen(events.add);

    final result = await auth.signInAnonymously();

    expect(
      requests.single.url.toString(),
      'https://fn.example.test/auth/sign-in/anonymous',
    );
    expect(requests.single.method, 'POST');
    expect(requests.single.body, '{}');
    expect(requests.single.headers['authorization'], isNull);
    expect(store.sessionToken, 'header-token');
    final user = (result as Success).data;
    expect(auth.currentUser?.id, 'u1');
    expect(auth.currentUser?.isAnonymous, isTrue);
    expect(auth.currentUser?.email, isNull, reason: 'guest email hidden');
    expect(user, auth.currentUser);
    await pumpEventQueue();
    expect(events, [AuthEvent.signedIn]);
  });

  test(
    'signUpEmail sends the guest bearer and adopts the new session',
    () async {
      store.sessionToken = 'guest-token';
      final auth = client(
        (req) async => _json({'token': 'new-token', 'user': userJson()}),
      );

      final result = await auth.signUpEmail('a@b.co', 'pw123456');

      final req = requests.single;
      expect(req.url.path, '/auth/sign-up/email');
      expect(req.headers['authorization'], 'Bearer guest-token');
      expect(jsonDecode(req.body), {'email': 'a@b.co', 'password': 'pw123456'});
      expect(result, isA<Success>());
      expect(store.sessionToken, 'new-token');
      expect(auth.currentUser?.providers, ['email']);
    },
  );

  test('signInEmail maps 401 to an auth error and keeps the guest', () async {
    store.sessionToken = 'guest-token';
    final auth = client(
      (req) async => _json({
        'code': 'INVALID_EMAIL_OR_PASSWORD',
        'message': 'Invalid email',
      }, 401),
    );
    final result = await auth.signInEmail('a@b.co', 'bad');
    expect((result as Failure).error, const AppError.auth('Invalid email'));
    expect(store.sessionToken, 'guest-token');
  });

  test('signInWithIdToken posts the native token body', () async {
    store.sessionToken = 'guest-token';
    final auth = client(
      (req) async => _json({'token': 't2', 'user': userJson()}),
    );
    await auth.signInWithIdToken(
      provider: 'apple',
      idToken: 'id-tok',
      nonce: 'n1',
    );
    expect(requests.single.url.path, '/auth/sign-in/social');
    expect(requests.single.headers['authorization'], 'Bearer guest-token');
    expect(jsonDecode(requests.single.body), {
      'provider': 'apple',
      'idToken': {'token': 'id-tok', 'nonce': 'n1'},
    });
    expect(store.sessionToken, 't2');
  });

  test('linkWithIdToken keeps the user and maps 409 to a conflict', () async {
    store.sessionToken = 'guest-token';
    var conflict = false;
    final auth = client((req) async {
      if (req.url.path == '/auth/link-social') {
        return conflict
            ? _json({
                'code': 'ACCOUNT_ALREADY_LINKED',
                'message': 'linked',
              }, 409)
            : _json({'status': true});
      }
      if (req.url.path == '/auth/get-session') {
        return _json({'session': {}, 'user': userJson(anonymous: true)});
      }
      if (req.url.path == '/auth/list-accounts') {
        return _json([
          {'providerId': 'anonymous'},
          {'providerId': 'google'},
        ]);
      }
      return http.Response('?', 404);
    });

    final ok = await auth.linkWithIdToken(provider: 'google', idToken: 'g');
    expect((ok as Success).data, isNotNull);
    expect(auth.currentUser?.id, 'u1');
    expect(auth.currentUser?.providers, ['google']);
    expect(store.sessionToken, 'guest-token');
    expect(requests.first.headers['authorization'], 'Bearer guest-token');

    conflict = true;
    final clash = await auth.linkWithIdToken(provider: 'google', idToken: 'g');
    expect((clash as Failure).error, isA<ConflictError>());
  });

  group('webOAuth', () {
    Future<http.Response> server(http.Request req) async {
      switch (req.url.path) {
        case '/auth/sign-in/social':
        case '/auth/link-social':
          return _json({'url': 'https://appleid.apple.com/auth?x=1&y=2'});
        case '/auth/get-session':
          return _json({'session': {}, 'user': userJson(id: 'u9')});
        case '/auth/list-accounts':
          return _json([
            {'providerId': 'apple'},
          ]);
      }
      return http.Response('?', 404);
    }

    test('parses the session cookie from the callback', () async {
      store.sessionToken = 'guest-token';
      Uri? opened;
      String? scheme;
      final auth = client(
        server,
        web: (url, s) async {
          opened = url;
          scheme = s;
          return 'io.icos://oauth-callback?cookie='
              '${Uri.encodeComponent('__Secure-better-auth.session_token=abc.def%3D; Path=/; HttpOnly; Secure')}';
        },
      );

      final result = await auth.webOAuth('apple');

      final start = requests.first;
      expect(start.url.path, '/auth/sign-in/social');
      expect(start.headers['authorization'], 'Bearer guest-token');
      expect(jsonDecode(start.body), {
        'provider': 'apple',
        'callbackURL': kOAuthCallbackUrl,
        'disableRedirect': true,
      });
      expect(scheme, 'io.icos');
      expect(opened!.path, '/auth/expo-authorization-proxy');
      expect(
        opened!.queryParameters['authorizationURL'],
        'https://appleid.apple.com/auth?x=1&y=2',
      );
      expect(store.sessionToken, 'abc.def=');
      expect((result as Success).data, isNotNull);
      expect(auth.currentUser?.id, 'u9');
      final session = requests.firstWhere(
        (r) => r.url.path == '/auth/get-session',
      );
      expect(session.headers['authorization'], 'Bearer abc.def=');
    });

    test('link uses link-social', () async {
      store.sessionToken = 'guest-token';
      final auth = client(
        server,
        web: (_, _) async =>
            'io.icos://oauth-callback?cookie=better-auth.session_token%3Dxyz',
      );
      await auth.webOAuth('apple', link: true);
      expect(requests.first.url.path, '/auth/link-social');
      expect(store.sessionToken, 'xyz');
    });

    test('error callback is an auth failure', () async {
      store.sessionToken = 'guest-token';
      final auth = client(
        server,
        web: (_, _) async => 'io.icos://oauth-callback?error=access_denied',
      );
      final result = await auth.webOAuth('apple');
      expect((result as Failure).error, const AppError.auth('access_denied'));
      expect(store.sessionToken, 'guest-token');
    });

    test('an unusable callback session keeps the guest session', () async {
      store.sessionToken = 'guest-token';
      final auth = client(
        (req) async => req.url.path == '/auth/get-session'
            ? http.Response('null', 200)
            : server(req),
        web: (_, _) async =>
            'io.icos://oauth-callback?cookie=better-auth.session_token%3Dbad',
      );
      final result = await auth.webOAuth('apple');
      expect(result, isA<Failure>());
      expect(store.sessionToken, 'guest-token');
    });

    test('a non-platform error from the browser is an auth failure', () async {
      final auth = client(server, web: (_, _) async => throw StateError('x'));
      final result = await auth.webOAuth('apple');
      expect((result as Failure).error, isA<AuthError>());
    });

    test('onBrowserClosed runs once the sheet is gone, before the exchange '
        'and on cancel, never when the browser never opened', () async {
      store.sessionToken = 'guest-token';
      final log = <String>[];
      final auth = client(
        (req) async {
          if (req.url.path == '/auth/get-session') log.add('exchange');
          return server(req);
        },
        web: (_, _) async {
          log.add('browser');
          return 'io.icos://oauth-callback?cookie=better-auth.session_token%3Dxyz';
        },
      );
      await auth.webOAuth('apple', onBrowserClosed: () => log.add('closed'));
      expect(log, ['browser', 'closed', 'exchange']);

      log.clear();
      final cancelled = client(
        server,
        web: (_, _) async => throw PlatformException(code: 'CANCELED'),
      );
      await cancelled.webOAuth('apple', onBrowserClosed: () => log.add('closed'));
      expect(log, ['closed']);

      log.clear();
      final noStart = client((_) async => http.Response('{}', 500));
      await noStart.webOAuth('apple', onBrowserClosed: () => log.add('closed'));
      expect(log, isEmpty);
    });

    test('dismissed browser is cancelled', () async {
      final auth = client(
        server,
        web: (_, _) async => throw PlatformException(code: 'CANCELED'),
      );
      final result = await auth.webOAuth('apple');
      expect((result as Failure).error, const AppError.cancelled());
    });
  });

  test('parseOAuthCallback picks the session cookie among others', () {
    final cookie = Uri.encodeComponent(
      'better-auth.state=s; Path=/, __Secure-better-auth.session_token=tok%2B1; Path=/',
    );
    final r = AuthClient.parseOAuthCallback(
      'io.icos://oauth-callback?cookie=$cookie',
    );
    expect((r as Success).data, 'tok+1');
    expect(
      AuthClient.parseOAuthCallback('io.icos://oauth-callback'),
      isA<Failure>(),
    );
    // Stops at ',' (several Set-Cookie headers joined).
    final joined = Uri.encodeComponent(
      'better-auth.session_token=abc,better-auth.other=x',
    );
    expect(
      (AuthClient.parseOAuthCallback('io.icos://oauth-callback?cookie=$joined')
              as Success)
          .data,
      'abc',
    );
    // Malformed percent-encoding never throws.
    final bad = Uri.encodeComponent('better-auth.session_token=%E0%A4%A');
    expect(
      AuthClient.parseOAuthCallback('io.icos://oauth-callback?cookie=$bad'),
      isA<Failure>(),
    );
    expect(
      AuthClient.parseOAuthCallback('io.icos://oauth-callback?cookie=%ZZ'),
      isA<Failure>(),
    );
  });

  test('freshJwt reuses a cached JWT and refreshes inside 60 s', () async {
    store.sessionToken = 's';
    final newJwt = fakeJwt(now.add(const Duration(minutes: 15)));
    final auth = client((req) async => _json({'token': newJwt}));

    store
      ..jwt = 'cached'
      ..expiry = now.add(const Duration(minutes: 5));
    expect(await auth.freshJwt(), 'cached');
    expect(requests, isEmpty);

    store.expiry = now.add(const Duration(seconds: 30));
    expect(await auth.freshJwt(), newJwt);
    expect(requests.single.url.path, '/auth/token');
    expect(requests.single.method, 'GET');
    expect(requests.single.headers['authorization'], 'Bearer s');
    expect(store.expiry, now.add(const Duration(minutes: 15)));
  });

  test('freshJwt is null when signed out and clears a dead session', () async {
    final auth = client((req) async => _json({'error': 'x'}, 401));
    expect(await auth.freshJwt(), isNull);
    expect(requests, isEmpty);

    store.sessionToken = 'dead';
    final events = <AuthEvent>[];
    auth.events.listen(events.add);
    expect(await auth.freshJwt(force: true), isNull);
    expect(store.sessionToken, isNull);
    await pumpEventQueue();
    expect(events, [AuthEvent.signedOut]);
  });

  test(
    'a refresh in flight across sign-out and a new guest is discarded',
    () async {
      store.sessionToken = 'old-session';
      final slowToken = Completer<http.Response>();
      final auth = client((req) async {
        switch (req.url.path) {
          case '/auth/token':
            return req.headers['authorization'] == 'Bearer old-session'
                ? slowToken.future
                : _json({
                    'token': fakeJwt(
                      now.add(const Duration(minutes: 15)),
                      sub: 'u2',
                    ),
                  });
          case '/auth/sign-out':
            return _json({'success': true});
          case '/auth/sign-in/anonymous':
            return _json({
              'token': 'new-session',
              'user': userJson(id: 'u2', anonymous: true),
            });
        }
        return http.Response('?', 404);
      });

      final stale = auth.freshJwt();
      await pumpEventQueue();
      await auth.signOut();
      await auth.signInAnonymously();
      final fresh = await auth.freshJwt();

      slowToken.complete(
        _json(
          {'token': fakeJwt(now.add(const Duration(minutes: 15)), sub: 'u1')},
          200,
          {'set-auth-token': 'old-rotated'},
        ),
      );
      expect(await stale, isNull);
      expect(store.sessionToken, 'new-session');
      expect(store.jwt, fresh);
      expect(fresh, isNotNull);
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(fresh!.split('.')[1])),
                ),
              )
              as Map<String, dynamic>;
      expect(payload['sub'], 'u2');
    },
  );

  test('parallel freshJwt calls share one /auth/token request', () async {
    store.sessionToken = 's';
    final gate = Completer<void>();
    final jwt = fakeJwt(now.add(const Duration(minutes: 15)));
    final auth = client((req) async {
      await gate.future;
      return _json({'token': jwt});
    });
    final calls = List.generate(5, (_) => auth.freshJwt());
    await pumpEventQueue();
    gate.complete();
    expect(await Future.wait(calls), List.filled(5, jwt));
    expect(requests.where((r) => r.url.path == '/auth/token'), hasLength(1));
  });

  test('getSession null clears the session', () async {
    store
      ..sessionToken = 's'
      ..userJson = jsonEncode(userJson());
    final auth = client((req) async => http.Response('null', 200));
    await auth.restore();
    expect(auth.currentUser?.id, 'u1');
    final events = <AuthEvent>[];
    auth.events.listen(events.add);

    final result = await auth.getSession();
    expect((result as Success).data, isNull);
    expect(auth.currentUser, isNull);
    expect(store.sessionToken, isNull);
    await pumpEventQueue();
    expect(events, [AuthEvent.signedOut]);
  });

  test('getSession offline keeps the session', () async {
    store.sessionToken = 's';
    final auth = client((req) async => throw http.ClientException('offline'));
    final result = await auth.getSession();
    expect((result as Failure).error, isA<NetworkError>());
    expect(store.sessionToken, 's');
  });

  test('signOut posts a JSON body with the bearer and clears', () async {
    store
      ..sessionToken = 's'
      ..jwt = 'j';
    final auth = client((req) async => _json({'success': true}));
    await auth.signOut();
    final req = requests.single;
    expect(req.url.path, '/auth/sign-out');
    expect(req.headers['authorization'], 'Bearer s');
    expect(req.headers['content-type'], startsWith('application/json'));
    expect(req.body, '{}');
    expect(store.sessionToken, isNull);
    expect(store.jwt, isNull);
  });

  test('upgradeEmail updates the user; 409 is a conflict', () async {
    store.sessionToken = 's';
    var status = 200;
    final auth = client(
      (req) async => status == 200
          ? _json({'user': userJson()})
          : _json({'error': 'Email taken', 'code': 'EMAIL_EXISTS'}, 409),
    );
    final ok = await auth.upgradeEmail('a@b.co', 'pw123456');
    expect(
      requests.single.url.toString(),
      'https://fn.example.test/api/account/upgrade-email',
    );
    expect(requests.single.headers['authorization'], 'Bearer s');
    expect((ok as Success).data, isNotNull);
    expect(auth.currentUser?.email, 'a@b.co');

    status = 409;
    final clash = await auth.upgradeEmail('a@b.co', 'pw123456');
    expect((clash as Failure).error, const AppError.conflict('Email taken'));
  });

  test('password reset and verification bodies', () async {
    final auth = client((req) async => _json({'status': true}));
    await auth.requestPasswordReset('a@b.co', redirectTo: 'https://x/reset');
    await auth.resetPassword('tok', 'newpw123');
    expect(jsonDecode(requests[0].body), {
      'email': 'a@b.co',
      'redirectTo': 'https://x/reset',
    });
    expect(requests[1].url.path, '/auth/reset-password');
    expect(jsonDecode(requests[1].body), {
      'newPassword': 'newpw123',
      'token': 'tok',
    });
    final noEmail = await auth.sendVerificationEmail();
    expect((noEmail as Failure).error, isA<ValidationError>());

    // Guest current user + explicit email (resend after a session-less
    // sign-up).
    store.sessionToken = 'guest';
    store.userJson = jsonEncode(userJson(anonymous: true));
    await auth.restore();
    expect(auth.currentUser?.email, isNull);
    final sent = await auth.sendVerificationEmail(email: 'new@b.co');
    expect(sent, isA<Success>());
    expect(requests.last.url.path, '/auth/send-verification-email');
    expect(jsonDecode(requests.last.body), {'email': 'new@b.co'});
  });
}

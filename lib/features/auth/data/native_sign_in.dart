import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../domain/auth_strategy.dart';

part 'native_sign_in.g.dart';

/// An ID token from a native sign-in SDK, ready for `AuthClient`.
class NativeIdToken {
  const NativeIdToken({required this.idToken, this.nonce});

  final String idToken;

  /// The raw nonce (Apple). The server accepts it raw or SHA-256 hashed.
  final String? nonce;
}

/// The native Google / Apple sheets. A seam so tests never touch the
/// platform channels.
///
/// Both methods throw the SDK's own exceptions on cancel or failure
/// (`GoogleSignInException`, `SignInWithAppleAuthorizationException`) and
/// return null when the SDK gave no ID token.
abstract class NativeSignIn {
  Future<NativeIdToken?> google({
    required AuthPlatform platform,
    required String? webClientId,
    required String? iosClientId,
  });

  Future<NativeIdToken?> apple();
}

class PlatformNativeSignIn implements NativeSignIn {
  bool _googleInitialized = false;

  @override
  Future<NativeIdToken?> google({
    required AuthPlatform platform,
    required String? webClientId,
    required String? iosClientId,
  }) async {
    final gsi = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await gsi.initialize(
        clientId: platform == AuthPlatform.ios ? iosClientId : null,
        serverClientId: webClientId,
      );
      _googleInitialized = true;
    }
    final account = await gsi.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) return null;
    return NativeIdToken(idToken: idToken);
  }

  @override
  Future<NativeIdToken?> apple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) return null;
    return NativeIdToken(idToken: idToken, nonce: rawNonce);
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}

@Riverpod(keepAlive: true)
NativeSignIn nativeSignIn(Ref ref) => PlatformNativeSignIn();

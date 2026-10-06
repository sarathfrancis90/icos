import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// The only place a web OAuth page is shown.
///
/// Apple (App Review Guideline 4, build 1.0.0 (4)) rejected the app for
/// sending people to the default browser to sign in. Web OAuth now runs in the
/// platform's authentication session: ASWebAuthenticationSession on iOS and a
/// Chrome Custom Tab plus the package's `CallbackActivity` on Android. Both
/// hand the redirect URL straight back to [authenticate] and dismiss
/// themselves, so nothing relies on the custom-scheme intent reaching
/// `MainActivity` or on the app closing a browser sheet.
///
/// supabase_flutter 2.12.0 is not used to launch the page: its
/// `signInWithOAuth`/`linkIdentity` open the system browser (and force it for
/// Google on Android). This gateway asks gotrue for the authorize URL, which
/// also stores the PKCE verifier exactly as the SDK does, shows it, then
/// finishes the sign-in with `getSessionFromUrl`, the SDK's own handler for
/// the redirect.
///
/// Tests replace [current] to run the flow without a network or a platform
/// channel.
class OAuthWebGateway {
  const OAuthWebGateway();

  /// Callback scheme registered for the session API (iOS) and for the
  /// Android `CallbackActivity`.
  static const String callbackScheme = 'io.supabase.icos';

  /// Swapped by tests; production never reassigns it.
  static OAuthWebGateway current = const OAuthWebGateway();

  /// Authorize URL for signing in (`link: false`) or for linking the
  /// current guest identity to a provider (`link: true`).
  Future<Uri> authorizeUrl(
    OAuthProvider provider, {
    required bool link,
    required String redirectTo,
  }) async {
    final res = link
        ? await SupabaseService.auth.getLinkIdentityUrl(
            provider,
            redirectTo: redirectTo,
          )
        : await SupabaseService.auth.getOAuthSignInUrl(
            provider: provider,
            redirectTo: redirectTo,
          );
    return Uri.parse(res.url);
  }

  /// Shows [url] in the authentication session and returns the redirect URL.
  ///
  /// Throws a `PlatformException` with code `CANCELED` when the person closes
  /// the sheet or tab (before or after it loaded).
  ///
  /// `preferEphemeral` keeps the session apart from Safari's cookies and
  /// suppresses iOS's "wants to use supabase.co to sign in" consent alert; the
  /// trade-off is no single sign-on from an existing Safari Google session.
  Future<Uri> authenticate(Uri url) async {
    final result = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: callbackScheme,
      options: const FlutterWebAuth2Options(preferEphemeral: true),
    );
    return Uri.parse(result);
  }

  /// Completes the sign-in from the redirect [callback] (PKCE code exchange).
  /// Emits the usual auth events; throws [AuthException] on a provider error.
  Future<void> completeSession(Uri callback) async {
    await SupabaseService.auth.getSessionFromUrl(callback);
  }
}

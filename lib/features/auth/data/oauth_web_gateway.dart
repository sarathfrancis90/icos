import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';

/// The only place a web OAuth page is opened or closed.
///
/// Apple (App Review Guideline 4, build 1.0.0 (4)) rejected the app for
/// sending people to the default browser to sign in. Every web flow now opens
/// in an in-app browser: SFSafariViewController on iOS, a Chrome Custom Tab
/// on Android (`LaunchMode.inAppBrowserView`).
///
/// supabase_flutter 2.12.0 is not used to launch the page: its
/// `signInWithOAuth`/`linkIdentity` force `externalApplication` for Google on
/// Android. This gateway asks gotrue for the authorize URL (which also stores
/// the PKCE verifier, exactly as the SDK does) and launches it itself.
///
/// Tests replace [current] to observe the launch mode without a network.
class OAuthWebGateway {
  const OAuthWebGateway();

  /// How every web OAuth page is shown. Never `externalApplication`.
  static const LaunchMode launchMode = LaunchMode.inAppBrowserView;

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

  /// Opens [url] in the in-app browser. False if it could not be shown.
  /// [mode] is always [launchMode]; it is a parameter so tests can assert it.
  Future<bool> launch(Uri url, LaunchMode mode) => launchUrl(url, mode: mode);

  /// Dismisses the in-app browser.
  ///
  /// iOS: url_launcher_ios 6.4.1 `closeSafariViewController` calls
  /// `safariViewControllerDidFinish`, which dismisses the presented
  /// SFSafariViewController. Android: only closes url_launcher's fallback
  /// WebViewActivity; a Custom Tab is not closed by this call (see the
  /// `launchMode` note in AndroidManifest.xml).
  Future<void> close() => closeInAppWebView();
}

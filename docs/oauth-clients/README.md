# Downloaded Google OAuth client files

Kept for reference only. **The app does not read any of these.**

Client ids reach the app as dart-defines from `.env.production`, via
`--dart-define-from-file`, and the iOS URL scheme is injected into `Info.plist`
at build time by `scripts/inject_google_url_scheme.sh`. Dropping these files
into `android/` or `ios/` has no effect, which is why they were moved here.

None of them contains a secret: the Android files and the iOS plist carry only
a client id. The one secret in this setup is the **web** client secret, which
lives in the Supabase dashboard and nowhere in this repo.

| File | Client | SHA-1 it was registered against |
|---|---|---|
| `...d1meldlrhel....json` | Android | Play app signing key |
| `...fc2vik9e4rs....json` | Android | Upload key |
| `...uganblnaf7r....json` | Android | Local debug keystore |
| `...29bmvc0vva....plist` | iOS | n/a, bundle id `com.icos.game` |

Not shown here: the **web** client `876802621972-tsu3ss64bros8iub3mijmraaj20m3t67`,
which is the one Supabase uses and the one Android sends as `serverClientId`.

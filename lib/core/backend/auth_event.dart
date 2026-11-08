/// Auth state changes broadcast by `AuthClient.events` (mirrors the subset
/// of Supabase's `AuthChangeEvent` the app listens to).
enum AuthEvent { signedIn, signedOut, userUpdated, passwordRecovery }

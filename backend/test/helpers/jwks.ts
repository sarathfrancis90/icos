// The test branch is reset from main, which carries main's ba.jwks signing key
// encrypted with main's BETTER_AUTH_SECRET. With the test secret Better Auth
// cannot decrypt it and every getSession that mints a JWT fails. This drops
// only the keys the test secret cannot decrypt; Better Auth then mints its own.
// Keys created by concurrently running test files (same secret) are kept.
import { symmetricDecrypt } from "better-auth/crypto";

type Query = <T>(text: string, params?: unknown[]) => Promise<T[]>;

export async function dropForeignJwks(q: Query, secret: string): Promise<number> {
  const keys = await q<{ id: string; privateKey: string }>(`SELECT id, "privateKey" FROM ba.jwks`);
  let dropped = 0;
  for (const key of keys) {
    const readable = await symmetricDecrypt({ key: secret, data: JSON.parse(key.privateKey) })
      .then(() => true)
      .catch(() => false);
    if (!readable) {
      await q(`DELETE FROM ba.jwks WHERE id = $1`, [key.id]);
      dropped += 1;
    }
  }
  return dropped;
}

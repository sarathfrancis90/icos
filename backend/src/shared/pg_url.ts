import type pg from "pg";

/**
 * Connection config for a Neon connection string. pg warns that
 * `sslmode=require` will change meaning, so ask for full certificate and host
 * verification explicitly instead; honour `channel_binding=require`.
 */
export function pgConfig(url: string): pg.ClientConfig {
  return {
    connectionString: url.replace(/([?&])sslmode=require\b/, "$1sslmode=verify-full"),
    enableChannelBinding: /[?&]channel_binding=require\b/.test(url),
  };
}

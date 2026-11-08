// GET /api/config (no auth): the app_config rows as one object, so the app's
// force-update / maintenance gate works before it has a session (Neon's Data
// API rejects requests without a JWT).
//
// 200 { config: { min_supported_version, latest_version, maintenance_mode, store_urls, ... } }
import { Hono } from "hono";
import { q } from "../db.js";
import { PUBLIC_READ_TTL_MS, TtlCache } from "../shared/ttl_cache.js";
import { type ApiDeps, methodNotAllowed, requestCtx } from "./common.js";

/** Public, cacheable for 5 minutes (CDN and client). */
export const PUBLIC_CACHE = { "Cache-Control": "public, max-age=300" };

/** app_config as served, kept in memory for 60 s so polling clients do not hit Postgres. */
export const configCache = new TtlCache<Record<string, unknown>>(PUBLIC_READ_TTL_MS, 1);

export function configRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/config", async (c) => {
    const r = requestCtx(c, deps, "config");
    if (c.req.method !== "GET") return methodNotAllowed(r);
    let config = configCache.get("config");
    if (config === undefined) {
      const rows = await q<{ key: string; value: unknown }>("SELECT key, value FROM public.app_config ORDER BY key");
      config = Object.fromEntries(rows.map((row) => [row.key, row.value]));
      configCache.set("config", config);
    }
    return r.ok({ config }, 200, PUBLIC_CACHE);
  });

  return app;
}

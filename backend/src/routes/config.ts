// GET /api/config (no auth): the app_config rows as one object, so the app's
// force-update / maintenance gate works before it has a session (Neon's Data
// API rejects requests without a JWT).
//
// 200 { config: { min_supported_version, latest_version, maintenance_mode, store_urls, ... } }
import { Hono } from "hono";
import { q } from "../db.js";
import { type ApiDeps, methodNotAllowed, requestCtx } from "./common.js";

/** Public, cacheable for 5 minutes (CDN and client). */
export const PUBLIC_CACHE = { "Cache-Control": "public, max-age=300" };

export function configRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/config", async (c) => {
    const r = requestCtx(c, deps, "config");
    if (c.req.method !== "GET") return methodNotAllowed(r);
    const rows = await q<{ key: string; value: unknown }>("SELECT key, value FROM public.app_config ORDER BY key");
    const config = Object.fromEntries(rows.map((row) => [row.key, row.value]));
    return r.ok({ config }, 200, PUBLIC_CACHE);
  });

  return app;
}

// Icos API — the single Neon Function hosting auth (/auth/*), the former
// edge functions (/api/*) and scheduled jobs (/cron/*).
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { getAuth, type Auth } from "./auth.js";
import { sendEmail } from "./email.js";
import { accountRoutes } from "./routes/account.js";
import type { ApiDeps } from "./routes/common.js";
import { groupRoutes } from "./routes/groups.js";
import { puzzleRoutes } from "./routes/puzzle.js";
import { scoreRoutes } from "./routes/score.js";
import { corsHeaders, correlationIdFrom, errorFields, errorResponse, Logger } from "./shared/http.js";

/** Optional overrides for the /api/* routes (tests stub email and logging). */
export type AppDeps = Partial<Omit<ApiDeps, "auth">>;

/** Builds the app; tests pass their own Better Auth instance and deps. */
export function createApp(auth: () => Auth = getAuth, deps: AppDeps = {}): Hono {
  const app = new Hono();
  const api: ApiDeps = {
    auth,
    sendEmail: deps.sendEmail ?? ((msg) => sendEmail(msg)),
    logger: deps.logger ?? ((fn, cid) => new Logger(fn, cid)),
  };

  app.get("/health", (c) =>
    c.json({ status: "ok", fn: "api", ts: new Date().toISOString() }),
  );

  // Better Auth: sign-in/up, sessions, /auth/token, /auth/jwks, OAuth callbacks.
  app.on(["GET", "POST"], "/auth/*", (c) => auth().handler(c.req.raw));

  // The former edge functions (same request/response contracts).
  app.options("/api/*", () => new Response("ok", { headers: corsHeaders }));
  app.route("/api", puzzleRoutes(api));
  app.route("/api", scoreRoutes(api));
  app.route("/api", groupRoutes(api));
  app.route("/api", accountRoutes(api));

  app.onError((err, c) => {
    // requireSession's 401 (and any other deliberate HTTP error) as built.
    if (err instanceof HTTPException) return err.getResponse();
    const cid = correlationIdFrom(c.req.raw);
    api.logger("api", cid).error("unhandled error", { path: c.req.path, ...errorFields(err) });
    return errorResponse(500, "Internal server error", "INTERNAL", cid);
  });

  return app;
}

export default createApp();

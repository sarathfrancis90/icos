// Icos API — the single Neon Function hosting auth (/auth/*), the former
// edge functions (/api/*) and scheduled jobs (/cron/*).
import { Hono } from "hono";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { getAuth, type Auth } from "./auth.js";
import { sendEmail } from "./email.js";
import { accountRoutes } from "./routes/account.js";
import type { ApiDeps } from "./routes/common.js";
import { cronRoutes, type CronOptions } from "./routes/cron.js";
import { configRoutes } from "./routes/config.js";
import { groupRoutes } from "./routes/groups.js";
import { puzzleRoutes } from "./routes/puzzle.js";
import { scoreRoutes } from "./routes/score.js";
import { correlationIdFrom, errorFields, errorResponse, Logger } from "./shared/http.js";

/** The website's origin (docs/reset.html POSTs /auth/reset-password from it). */
export const WEB_ORIGIN = "https://icos.sarathfrancis.work";

/** Optional overrides for the /api/* and /cron/* routes (tests stub email, logging and jobs). */
export type AppDeps = Partial<Omit<ApiDeps, "auth">> & { cron?: CronOptions };

/** Builds the app; tests pass their own Better Auth instance and deps. */
export function createApp(auth: () => Auth = getAuth, deps: AppDeps = {}): Hono {
  const app = new Hono();
  const api: ApiDeps = {
    auth,
    sendEmail: deps.sendEmail ?? ((msg) => sendEmail(msg)),
    logger: deps.logger ?? ((fn, cid) => new Logger(fn, cid)),
  };

  // Browser CORS for the website only. A request without an Origin header (the
  // app) passes through untouched; a preflight from another origin gets no
  // Access-Control-Allow-Origin, so the browser blocks it.
  const webCors = cors({
    origin: [WEB_ORIGIN],
    allowMethods: ["GET", "POST", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
    maxAge: 600,
    credentials: false,
  });
  app.use("/auth/*", webCors);
  app.use("/api/*", webCors);

  app.get("/health", (c) =>
    c.json({ status: "ok", fn: "api", ts: new Date().toISOString() }),
  );

  // Better Auth: sign-in/up, sessions, /auth/token, /auth/jwks, OAuth callbacks.
  app.on(["GET", "POST"], "/auth/*", (c) => auth().handler(c.req.raw));

  // The former edge functions (same request/response contracts).
  app.route("/api", puzzleRoutes(api));
  app.route("/api", scoreRoutes(api));
  app.route("/api", groupRoutes(api));
  app.route("/api", accountRoutes(api));
  app.route("/api", configRoutes(api));

  // Neon schedule triggers (neon.ts `triggers`).
  app.route("/cron", cronRoutes(api, deps.cron));

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

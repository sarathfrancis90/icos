// Icos API — the single Neon Function hosting auth (/auth/*), the former
// edge functions (/api/*) and scheduled jobs (/cron/*).
import { Hono } from "hono";
import { getAuth, type Auth } from "./auth.js";

/** Builds the app; tests pass their own Better Auth instance. */
export function createApp(auth: () => Auth = getAuth): Hono {
  const app = new Hono();

  app.get("/health", (c) =>
    c.json({ status: "ok", fn: "api", ts: new Date().toISOString() }),
  );

  // Better Auth: sign-in/up, sessions, /auth/token, /auth/jwks, OAuth callbacks.
  app.on(["GET", "POST"], "/auth/*", (c) => auth().handler(c.req.raw));

  return app;
}

export default createApp();

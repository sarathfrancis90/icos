// Icos API — the single Neon Function hosting auth (/auth/*), the former
// edge functions (/api/*) and scheduled jobs (/cron/*).
//
// Task 1 ships only the health check and a placeholder JWKS so the Data API
// can be registered against this host; later tasks mount the real routers.
import { Hono } from "hono";

const app = new Hono();

app.get("/health", (c) =>
  c.json({ status: "ok", fn: "api", ts: new Date().toISOString() }),
);

// Replaced by Better Auth's JWT plugin in Task 5.
app.get("/auth/jwks", (c) => c.json({ keys: [] }));

export default app;

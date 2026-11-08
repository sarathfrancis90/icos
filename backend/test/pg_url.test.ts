import { test } from "node:test";
import assert from "node:assert/strict";
import { pgConfig } from "../src/shared/pg_url.js";

test("pgConfig upgrades sslmode=require to verify-full", () => {
  const cfg = pgConfig("postgresql://u:p@h.example/db?sslmode=require&channel_binding=require");
  assert.equal(cfg.connectionString, "postgresql://u:p@h.example/db?sslmode=verify-full&channel_binding=require");
  assert.equal(cfg.enableChannelBinding, true);
});

test("pgConfig rewrites sslmode when it is not the first parameter", () => {
  const cfg = pgConfig("postgresql://u:p@h.example/db?application_name=x&sslmode=require");
  assert.equal(cfg.connectionString, "postgresql://u:p@h.example/db?application_name=x&sslmode=verify-full");
  assert.equal(cfg.enableChannelBinding, false);
});

test("pgConfig leaves other sslmodes and plain URLs alone", () => {
  for (const url of [
    "postgresql://u:p@h.example/db?sslmode=disable",
    "postgresql://u:p@h.example/db?sslmode=requirex",
    "postgresql://localhost/db",
  ]) {
    assert.equal(pgConfig(url).connectionString, url);
  }
});

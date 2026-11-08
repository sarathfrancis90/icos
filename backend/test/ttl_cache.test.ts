import { test } from "node:test";
import assert from "node:assert/strict";
import { TtlCache } from "../src/shared/ttl_cache.js";

test("TtlCache serves a value until the TTL passes, then forgets it", () => {
  let now = 1_000;
  const cache = new TtlCache<string>(60_000, 64, () => now);
  assert.equal(cache.get("k"), undefined);
  cache.set("k", "v");
  now += 59_999;
  assert.equal(cache.get("k"), "v");
  now += 1;
  assert.equal(cache.get("k"), undefined);
});

test("TtlCache evicts the oldest entry beyond maxEntries; clear empties it", () => {
  const cache = new TtlCache<number>(60_000, 2, () => 0);
  cache.set("a", 1);
  cache.set("b", 2);
  cache.set("c", 3);
  assert.equal(cache.get("a"), undefined);
  assert.equal(cache.get("b"), 2);
  assert.equal(cache.get("c"), 3);
  cache.clear();
  assert.equal(cache.get("b"), undefined);
});

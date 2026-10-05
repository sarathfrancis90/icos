function assertEquals(a: unknown, b: unknown): void {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}
function assertThrows(fn: () => unknown): void {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error("expected throw");
}
import { blocksFromResult, isMissingRelation } from "./blocks.ts";

Deno.test("block rows are exported as ids and timestamps only", () => {
  const out = blocksFromResult({
    data: [{ blocked_id: "u2", created_at: "2026-10-01T00:00:00Z" }],
    error: null,
  });
  assertEquals(out, [{ blocked_user_id: "u2", blocked_at: "2026-10-01T00:00:00Z" }]);
});

Deno.test("a missing table is an empty list", () => {
  for (const error of [
    { code: "42P01", message: 'relation "public.user_blocks" does not exist' },
    { code: "PGRST205", message: "Could not find the table 'public.user_blocks' in the schema cache" },
  ]) {
    assertEquals(isMissingRelation(error), true);
    assertEquals(blocksFromResult({ data: null, error }), []);
  }
});

Deno.test("other errors still fail the export", () => {
  assertThrows(() => blocksFromResult({ data: null, error: { code: "XX000", message: "boom" } }));
});

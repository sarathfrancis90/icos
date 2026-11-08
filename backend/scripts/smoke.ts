// End-to-end smoke test against a deployed branch:
//   npm run smoke -- --api https://<function host>/ --date 2026-11-10
// Flow: anonymous sign-in → /auth/token → /api/start-puzzle → solve the puzzle
// locally (same salt as the server) → HMAC-sign → /api/submit-score.
// Needs PUZZLE_SEED_SALT in the environment (the branch's salt). Prints no secrets.
import { generatePuzzle, seedFor, weekdayDifficulty } from "../src/shared/puzzle_core.js";
import { hmacSha256Hex, scoreMessage, sha256Hex, utcToday } from "../src/shared/http.js";

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main(): Promise<number> {
  const api = (arg("api") ?? "").replace(/\/?$/, "/");
  const date = arg("date") ?? utcToday();
  const salt = process.env.PUZZLE_SEED_SALT;
  if (!api || !salt) {
    console.error("usage: smoke --api <function url> [--date YYYY-MM-DD]  (PUZZLE_SEED_SALT required)");
    return 2;
  }
  let failed = false;
  const step = (name: string, ok: boolean, extra = "") => {
    if (!ok) failed = true;
    console.log(`${ok ? "PASS" : "FAIL"} ${name} ${extra}`.trim());
  };
  // A gateway page or empty body must produce a FAIL line, not a parse crash.
  const readJson = async <T,>(res: Response): Promise<Partial<T>> => {
    try {
      return (await res.json()) as T;
    } catch {
      return {};
    }
  };

  const signIn = await fetch(`${api}auth/sign-in/anonymous`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
  const session = signIn.headers.get("set-auth-token") ?? "";
  step("anonymous sign-in", signIn.status === 200 && session.length > 0, `status ${signIn.status}`);
  if (!session) return 1;
  const auth = { authorization: `Bearer ${session}` };

  const tokenRes = await fetch(`${api}auth/token`, { headers: auth });
  const { token } = await readJson<{ token?: string }>(tokenRes);
  step("jwt", tokenRes.status === 200 && Boolean(token), `status ${tokenRes.status}`);

  const start = await fetch(`${api}api/start-puzzle`, { method: "POST", headers: { ...auth, "content-type": "application/json" }, body: JSON.stringify({ puzzle_date: date }) });
  const startBody = await readJson<{ nonce?: string; already_completed?: boolean; code?: string }>(start);
  step("start-puzzle", start.status === 200 && Boolean(startBody.nonce), `status ${start.status} ${startBody.code ?? ""}`);
  if (!startBody.nonce) return 1;

  const { gridSize, difficulty } = weekdayDifficulty(date);
  // Same node budget as the server (src/routes/puzzle.ts) so both derive the same puzzle.
  const puzzle = generatePuzzle({ size: gridSize, difficulty, seed: seedFor(date, salt), nodeBudget: 2_000_000 });
  const path = puzzle.referencePath;
  const timeSeconds = 42;
  const pathHash = await sha256Hex(JSON.stringify(path));
  const signature = await hmacSha256Hex(startBody.nonce, scoreMessage(date, timeSeconds, 0, 0, pathHash));
  const submit = await fetch(`${api}api/submit-score`, {
    method: "POST",
    headers: { ...auth, "content-type": "application/json" },
    body: JSON.stringify({ puzzle_date: date, time_seconds: timeSeconds, hints_used: 0, undos_used: 0, path, signature }),
  });
  const submitBody = await readJson<{ completed?: boolean; verified?: boolean; is_archive?: boolean; streak?: { current_streak?: number }; code?: string; reason?: string }>(submit);
  step("submit-score", submit.status === 200 && submitBody.completed === true && submitBody.verified === true,
    `status ${submit.status} verified=${submitBody.verified} archive=${submitBody.is_archive} streak=${submitBody.streak?.current_streak} ${submitBody.code ?? submitBody.reason ?? ""}`);

  const again = await fetch(`${api}api/submit-score`, {
    method: "POST",
    headers: { ...auth, "content-type": "application/json" },
    body: JSON.stringify({ puzzle_date: date, time_seconds: timeSeconds, hints_used: 0, undos_used: 0, path, signature }),
  });
  step("submit-score repeat → 409", again.status === 409, `status ${again.status}`);

  const out = await fetch(`${api}auth/sign-out`, { method: "POST", headers: { ...auth, "content-type": "application/json" }, body: "{}" });
  step("sign-out", out.status === 200, `status ${out.status}`);
  return failed ? 1 : 0;
}

main().then((c) => process.exit(c), (e) => { console.error(e instanceof Error ? e.message : String(e)); process.exit(1); });

// Better Auth instance for the CLI only, which needs a module exporting `auth`:
//
//   DATABASE_URL=<test branch> npm run auth:generate
//
// writes .better-auth.generated.sql: the DDL behind migrations/0004_better_auth.sql
// for a branch without the `ba` schema, or the missing DDL after a Better Auth
// upgrade. Copy it into a new numbered migration, hand-adjusted like 0004, and
// delete the generated file. Deploys never run the CLI: our
// migration runner applies the committed SQL. The schema does not depend on
// the secret, base URL or providers, so placeholders are fine here.
import { createAuth } from "../src/auth.js";
import { sendEmail } from "../src/email.js";

export const auth = createAuth({
  sendEmail,
  baseURL: "http://localhost",
  secret: "schema-generation-only-not-a-real-secret",
});

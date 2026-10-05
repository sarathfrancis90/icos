// The caller's block list for the data export. The table ships in a
// migration that may not be applied yet, so a missing relation is an empty
// list, not a failed export.

export interface BlockQueryResult {
  data: { blocked_id: string; created_at: string }[] | null;
  error: { code?: string; message?: string } | null;
}

/** Postgres undefined_table, or PostgREST "table not in the schema cache". */
export function isMissingRelation(error: { code?: string; message?: string }): boolean {
  if (error.code === "42P01" || error.code === "PGRST205") return true;
  return /relation .* does not exist|could not find the table/i.test(error.message ?? "");
}

/** Block rows as `{ blocked_user_id, blocked_at }` (ids and timestamps only). */
export function blocksFromResult(res: BlockQueryResult): { blocked_user_id: string; blocked_at: string }[] {
  if (res.error) {
    if (isMissingRelation(res.error)) return [];
    throw new Error(`export query failed: ${res.error.message}`);
  }
  return (res.data ?? []).map((r) => ({ blocked_user_id: r.blocked_id, blocked_at: r.created_at }));
}

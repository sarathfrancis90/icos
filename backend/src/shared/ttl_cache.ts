// A tiny in-process cache with a fixed time-to-live, for public reads that
// clients poll (GET /api/config, GET /api/puzzle/:date). Each Function instance
// keeps its own copy, so a value can be up to `ttlMs` stale.

export class TtlCache<V> {
  private readonly entries = new Map<string, { value: V; expires: number }>();

  constructor(
    private readonly ttlMs: number,
    private readonly maxEntries = 64,
    private readonly now: () => number = Date.now,
  ) {}

  get(key: string): V | undefined {
    const entry = this.entries.get(key);
    if (entry === undefined) return undefined;
    if (entry.expires <= this.now()) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  set(key: string, value: V): void {
    this.entries.delete(key);
    if (this.entries.size >= this.maxEntries) {
      // Maps iterate in insertion order: drop the oldest entry.
      const oldest = this.entries.keys().next().value;
      if (oldest !== undefined) this.entries.delete(oldest);
    }
    this.entries.set(key, { value, expires: this.now() + this.ttlMs });
  }

  clear(): void {
    this.entries.clear();
  }
}

/** How long public reads are served from memory. */
export const PUBLIC_READ_TTL_MS = 60_000;

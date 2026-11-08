#!/usr/bin/env python3
"""Print the Icos Neon project's usage for the current billing period against the Free-plan caps.

Usage: python3 scripts/neon_usage.py [--project plain-wind-90305415]

Uses the signed-in Neon CLI (`neon api`), so no API key is needed. The Free plan allows
100 CU-hours of compute, 5 GB of public network transfer and 1 GB of storage per project;
compute and egress over the cap suspend the compute until the next period.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

FREE_CU_HOURS = 100.0
FREE_EGRESS_GB = 5.0
FREE_STORAGE_GB = 1.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="plain-wind-90305415")
    args = ap.parse_args()
    out = subprocess.run(["neon", "api", f"/projects/{args.project}"], capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stderr.strip() or "neon api failed", file=sys.stderr)
        return 1
    try:
        body = json.loads(out.stdout[out.stdout.index("{"):])
    except (ValueError, json.JSONDecodeError):
        print("unexpected response from neon api", file=sys.stderr)
        return 1
    p = body.get("project", body)
    cu_hours = p.get("compute_time_seconds", 0) / 3600
    active_hours = p.get("active_time_seconds", 0) / 3600
    egress_gb = p.get("data_transfer_bytes", 0) / 1e9
    storage_gb = p.get("synthetic_storage_size", 0) / 1e9
    period = f"{p.get('consumption_period_start', '?')[:10]} → {p.get('consumption_period_end', '?')[:10]}"

    def bar(used: float, cap: float) -> str:
        pct = 0 if cap == 0 else used / cap * 100
        return f"{used:8.3f} / {cap:g}  ({pct:5.1f}%)"

    print(f"Neon project {p.get('name', args.project)} — period {period}")
    print(f"  compute (CU-hours)  {bar(cu_hours, FREE_CU_HOURS)}   active hours {active_hours:.2f}")
    print(f"  egress (GB)         {bar(egress_gb, FREE_EGRESS_GB)}")
    print(f"  storage (GB)        {bar(storage_gb, FREE_STORAGE_GB)}")
    worst = max(cu_hours / FREE_CU_HOURS, egress_gb / FREE_EGRESS_GB, storage_gb / FREE_STORAGE_GB)
    if worst >= 0.8:
        print("WARNING: within 20% of a Free-plan cap")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

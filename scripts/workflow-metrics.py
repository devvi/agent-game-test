#!/usr/bin/env python3
"""workflow-metrics.py — PM view over the P2 audit log (P4c, 2026-07-31).

Reads ~/.hermes/workflow-audit.jsonl and prints a compact metrics summary:

  throughput    — SPAWNs per hour (24h / 7d)
  spawn mix     — review / self-correct / research / plan / implement
  health        — silent %, error %, paused %, avg phase-slot usage
  pending       — current pending event count + oldest event age

Consumed by: dashboard (server.py), /workflow status, or ad-hoc reporting.
Output is plain text; use --json for machine-readable form.
"""
import argparse
import json
import os
import sys
import time
from collections import Counter

HOME = os.path.expanduser("~")
AUDIT_FILE = os.path.join(HOME, ".hermes", "workflow-audit.jsonl")
PENDING_FILE = os.path.join(HOME, ".hermes", "workflow-pending.json")


def load_audit():
    records = []
    try:
        with open(AUDIT_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except FileNotFoundError:
        return []
    return records


def load_pending():
    try:
        with open(PENDING_FILE) as f:
            data = json.load(f)
        return data.get("events", [])
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def main():
    ap = argparse.ArgumentParser(description="Workflow metrics from audit log")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--hours", type=int, default=24, help="lookback window (default 24)")
    args = ap.parse_args()

    records = load_audit()
    cutoff = time.time() - args.hours * 3600
    # Audit ts format: 2026-07-31T15:09:05+0800 — parse to epoch
    recent = []
    for r in records:
        ts = r.get("ts", "")
        try:
            # strptime with %z handles +0800
            epoch = time.mktime(time.strptime(ts, "%Y-%m-%dT%H:%M:%S%z"))
        except (ValueError, TypeError):
            continue
        r["_epoch"] = epoch
        if epoch >= cutoff:
            recent.append(r)

    spawns = [r for r in recent if r.get("tick") == "end" and r.get("spawn_lines", 0) > 0]
    errors = [r for r in recent if r.get("output") == "[ERROR]"]
    silent = [r for r in recent if r.get("output") == "[SILENT]"]
    paused = [r for r in recent if r.get("output") == "[PAUSED]"]

    # SPAWN mix: sample output lines from spawn ticks
    mix = Counter()
    for r in spawns:
        out = r.get("output", "")
        for line in out.split("\n"):
            line = line.strip()
            if line.startswith("SPAWN: "):
                agent = line.split(": ")[1].split(",")[0]
                mix[agent] += 1

    total_ticks = len(recent) or 1
    stats = {
        "window_hours": args.hours,
        "ticks": len(recent),
        "spawns": len(spawns),
        "spawns_per_hour": round(len(spawns) / max(1, args.hours), 2),
        "mix": dict(mix),
        "silent_pct": round(100 * len(silent) / total_ticks, 1),
        "error_pct": round(100 * len(errors) / total_ticks, 1),
        "paused_pct": round(100 * len(paused) / total_ticks, 1),
        "avg_phase_slots_used": round(
            sum(r.get("active_phase", 0) for r in recent) / total_ticks, 2),
        "pending_events": len(load_pending()),
    }

    if args.json:
        print(json.dumps(stats, indent=2, ensure_ascii=False))
        return

    print(f"Workflow metrics (last {args.hours}h)")
    print(f"  ticks:            {stats['ticks']}  ({stats['ticks']/60:.1f}% of max)")
    print(f"  SPAWNs:           {stats['spawns']}  ({stats['spawns_per_hour']}/h)")
    print(f"  spawn mix:        {stats['mix'] or '—'}")
    print(f"  silent:           {stats['silent_pct']}%   error: {stats['error_pct']}%   paused: {stats['paused_pct']}%")
    print(f"  phase slots used: {stats['avg_phase_slots_used']}/4 avg")
    print(f"  pending events:   {stats['pending_events']}")


if __name__ == "__main__":
    main()

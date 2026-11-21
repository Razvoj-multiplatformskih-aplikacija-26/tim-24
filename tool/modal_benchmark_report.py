"""Collect public Modal billing evidence for the Hedrion benchmark.

This tool performs only read-only CLI calls. It never deploys, invokes a model,
changes billing settings, or claims a GPU-duration estimate is an invoice.
The per-app metered totals include preparation and failed attempts when these
used the same app. Credits are workspace-level adjustments, not per-call tokens.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_APP_PREFIXES = {
    "qwen_image_21_turbo": ("hedrion-qwen-",),
    "spar3d": ("hedrion-spar3d",),
    "hunyuan3d_21": ("hedrion-hunyuan",),
    "trellis2": ("hedrion-trellis2",),
    "shared_gateway": ("hedrion-modal-gateway",),
}


def modal_json(*args: str):
    result = subprocess.run(
        [sys.executable, "-m", "modal", "billing", *args, "--json"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=120,
        check=True,
    )
    return json.loads(result.stdout)


def collect(day: date) -> dict:
    # Full-day boundaries include the current hour. Modal can publish partial
    # usage with a delay, so a snapshot remains provisional while work runs.
    report = modal_json(
        "report", "--start", day.isoformat(),
        "--end", (day + timedelta(days=1)).isoformat(),
        "--resolution", "h", "--show-resources",
    )
    rates = modal_json("rates")
    return {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "benchmark_day_utc": day.isoformat(),
        "source": "Official Modal CLI: billing summary/report/rates --json",
        "summary": modal_json("summary", "--for", day.strftime("%Y-%m")),
        "hedrion_report": [
            row for row in report
            if row.get("description", "").startswith("hedrion-")
        ],
        "rates": {
            key: rates[key] for key in (
                "gpu_hour_cost_l4", "gpu_hour_cost_l40s", "cpu_hour_cost",
                "mem_gib_hour_cost", "volume_storage_gib_month_cost",
                "egress_gib_cost",
            ) if key in rates
        },
        "limitations": [
            "Metered app cost is before workspace credits/allowances.",
            "Per-app cost can include builds, downloads and failed attempts.",
            "The current interval may be incomplete; billing ingestion can lag.",
            "GPU-duration estimates exclude CPU, memory, idle time and storage.",
        ],
    }


def app_totals(snapshot: dict) -> dict[str, dict[str, Decimal]]:
    totals = defaultdict(lambda: defaultdict(Decimal))
    for row in snapshot.get("hedrion_report", []):
        totals[row["description"]][row.get("resource", "Other")] += Decimal(row["cost"])
    return totals


def write_comparison(folder: Path, baseline: dict, after: dict) -> None:
    before_totals, after_totals = app_totals(baseline), app_totals(after)
    rows = []
    for name in sorted(set(before_totals) | set(after_totals)):
        resources = {}
        for resource in sorted(set(before_totals[name]) | set(after_totals[name])):
            resources[resource] = str(after_totals[name][resource] - before_totals[name][resource])
        rows.append({
            "app": name,
            "metered_usd_for_day": str(sum(after_totals[name].values(), Decimal(0))),
            "compute_usd_for_day": str(sum(
                (value for resource, value in after_totals[name].items()
                 if resource in {"CPU", "Memory", "L4", "L40S"}), Decimal(0)
            )),
            "gpu_usd_for_day": str(sum(
                (value for resource, value in after_totals[name].items()
                 if resource in {"L4", "L40S"}), Decimal(0)
            )),
            "network_egress_usd_for_day": str(after_totals[name]["Network Egress"]),
            "metered_usd_since_baseline": str(sum(map(Decimal, resources.values()), Decimal(0))),
            "resources_usd_for_day": {key: str(value) for key, value in after_totals[name].items()},
            "resources_usd_since_baseline": resources,
            "attribution": "All reported app use, including preparation and failures",
        })
    (folder / "billing-app-costs.json").write_text(
        json.dumps({"captured_at_utc": after["captured_at_utc"], "apps": rows}, indent=2),
        encoding="utf-8",
    )
    with (folder / "billing-app-costs.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=[
            "app", "metered_usd_for_day", "compute_usd_for_day", "gpu_usd_for_day",
            "network_egress_usd_for_day", "metered_usd_since_baseline",
            "resources_usd_for_day", "resources_usd_since_baseline", "attribution",
        ])
        writer.writeheader()
        writer.writerows(rows)
    model_rows = []
    for provider, prefixes in MODEL_APP_PREFIXES.items():
        related = [row for row in rows if row["app"].startswith(prefixes)]
        model_rows.append({
            "provider": provider,
            "apps": ", ".join(row["app"] for row in related),
            **{
                key: str(sum((Decimal(row[key]) for row in related), Decimal(0)))
                for key in (
                    "metered_usd_for_day", "compute_usd_for_day", "gpu_usd_for_day",
                    "network_egress_usd_for_day",
                )
            },
            "scope": "All reported preparation, downloads, attempts and idle time; before credits",
        })
    (folder / "billing-model-costs.json").write_text(json.dumps({
        "captured_at_utc": after["captured_at_utc"],
        "models": model_rows,
        "limitations": after["limitations"],
    }, indent=2), encoding="utf-8")
    with (folder / "billing-model-costs.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(model_rows[0]))
        writer.writeheader()
        writer.writerows(model_rows)
    print(json.dumps({"captured_at_utc": after["captured_at_utc"], "apps": rows}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--day", type=date.fromisoformat, default=date(2026, 11, 14))
    parser.add_argument("--snapshot", choices=("baseline", "after"), default="after")
    args = parser.parse_args()
    folder = ROOT / ".local" / "benchmarks" / args.day.isoformat()
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder / f"billing-{args.snapshot}.json"
    if args.snapshot == "baseline" and destination.exists():
        parser.error("The baseline already exists and will not be overwritten.")
    snapshot = collect(args.day)
    destination.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")
    baseline_path = folder / "billing-baseline.json"
    if args.snapshot == "after" and baseline_path.exists():
        write_comparison(folder, json.loads(baseline_path.read_text(encoding="utf-8")), snapshot)
    else:
        print(json.dumps({"saved": str(destination), "hedrion_rows": len(snapshot["hedrion_report"]), "rates": snapshot["rates"]}, indent=2))


if __name__ == "__main__":
    main()

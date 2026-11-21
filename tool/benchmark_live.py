"""One durable, explicitly selected live benchmark through the Hedrion HTTP API.

Existing state resumes polling; it never automatically buys a replacement job.
Credentials and intermediate state remain under gitignored .local/.
"""
from __future__ import annotations

import argparse
import json
import secrets
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROMPT = (
    "A single whimsical brass clockwork owl figurine, complete object centered, "
    "three-quarter view, clear silhouette, realistic materials, plain white "
    "background, no text, no pedestal"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("provider", choices=["spar3d", "hunyuan3d_21", "trellis2"])
    parser.add_argument("--text", action="store_true")
    parser.add_argument("--run", default="", help="Explicit label for a new paid run; omit to resume the existing run")
    parser.add_argument("--directory", type=Path, default=ROOT / ".local/benchmarks/2026-11-14")
    args = parser.parse_args()
    config = dict(
        line.split("=", 1) for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#") and "=" in line
    )
    base = "http://127.0.0.1:" + config.get("API_PORT", "18080")
    args.directory.mkdir(parents=True, exist_ok=True)
    name = args.provider + ("-text" if args.text else "-image")
    if args.run:
        if not all(c.isalnum() or c in "_-" for c in args.run):
            parser.error("--run must contain only letters, numbers, underscores or hyphens")
        name += "-" + args.run
    completed_report = args.directory / (name + ".live.json")
    if completed_report.exists():
        print(completed_report.read_text(encoding="utf-8"), flush=True)
        return
    state_file = args.directory / (name + ".state.json")
    state = json.loads(state_file.read_text()) if state_file.exists() else {}

    def save() -> None:
        state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")

    def request(method: str, path: str, body=None, *, binary=None, key=None, revision=None):
        headers = {"Content-Type": "application/json"}
        if state.get("token"):
            headers["Authorization"] = "Bearer " + state["token"]
        if key:
            headers["Idempotency-Key"] = key
        if revision is not None:
            headers["If-Match"] = str(revision)
        data = None if body is None else json.dumps(body).encode()
        if binary is not None:
            data = binary
            headers.update({"Content-Type": "image/png", "X-File-Length": str(len(binary))})
        req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                content = response.read()
                return json.loads(content) if "json" in response.headers.get("Content-Type", "") else content
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"HTTP {error.code}: {error.read(4096).decode(errors='replace')}") from None

    if "token" not in state:
        state["password"] = secrets.token_urlsafe(22)
        state["email"] = f"benchmark-{name}-{secrets.token_hex(4)}@hedrion.test"
        session = request("POST", "/api/v1/auth/register", {
            "email": state["email"], "password": state["password"],
            "displayName": "Modal benchmark " + args.provider,
        })
        state["token"] = session["token"]
        save()
    if "asset" not in state:
        state["asset"] = request("POST", "/api/v1/assets", {
            "title": "Clockwork owl " + args.provider + (" " + args.run if args.run else ""),
            "description": PROMPT, "category": "props",
        })
        if "asset" in state["asset"]:
            state["asset"] = state["asset"]["asset"]
        save()
    asset = state["asset"]
    asset_path = "/api/v1/assets/" + asset["id"]
    if not args.text and not state.get("uploaded"):
        result = request("PUT", asset_path + "/source", binary=(args.directory / "reference.png").read_bytes())
        state["asset"] = asset = result["asset"]
        state["uploaded"] = True
        save()
    if "job" not in state:
        # Store timestamp and key BEFORE dispatch, so an interrupted HTTP response
        # can replay the exact admission rather than purchase another inference.
        state.setdefault("submittedAt", datetime.now(timezone.utc).isoformat())
        state.setdefault("commandKey", "benchmark-" + secrets.token_hex(16))
        save()
        result = request("POST", asset_path + "/generations", {
            "baseRevision": asset["revision"], "modelProvider": args.provider,
            "inputType": "text_to_3d" if args.text else "image_to_3d",
            "sourcePrompt": PROMPT if args.text else None, "seed": 42,
        }, key=state["commandKey"], revision=asset["revision"])
        state["job"] = result["job"]
        save()
        print(json.dumps({"provider": args.provider, "jobId": state["job"]["id"], "status": "accepted"}), flush=True)
    deadline = time.monotonic() + 2100
    last = None
    while True:
        job = request("GET", "/api/v1/generations/" + state["job"]["id"])
        if "job" in job:
            job = job["job"]
        state["job"] = job
        save()
        if job["status"] != last:
            print(json.dumps({"provider": args.provider, "status": job["status"]}), flush=True)
            last = job["status"]
        if job["status"] in ("succeeded", "failed", "cancelled"):
            break
        if time.monotonic() > deadline:
            raise TimeoutError("Benchmark still pending; rerun to resume polling without another purchase.")
        time.sleep(5)
    if job["status"] != "succeeded":
        raise RuntimeError(json.dumps({"provider": args.provider, "failureCode": job.get("failureCode"), "message": job.get("failureMessage")}))
    asset = request("GET", asset_path)
    asset = asset.get("asset", asset)
    download = request("GET", asset_path + "/download-url")
    model = request("GET", download["url"])
    if not isinstance(model, bytes) or model[:4] != b"glTF":
        raise RuntimeError("Downloaded result is not GLB")
    (args.directory / (name + ".glb")).write_bytes(model)
    preview = request("GET", "/api/v1/files/" + asset["previewFileId"])
    (args.directory / (name + ".png")).write_bytes(preview)
    finished = datetime.now(timezone.utc)
    report = {
        "provider": args.provider, "inputType": "text_to_3d" if args.text else "image_to_3d",
        "jobId": job["id"], "assetId": asset["id"], "prompt": PROMPT,
        "submittedAt": state["submittedAt"], "finishedAt": finished.isoformat(),
        "client_elapsed_ms": round((finished - datetime.fromisoformat(state["submittedAt"])).total_seconds() * 1000),
        "downloaded_glb_bytes": len(model), "downloaded_preview_bytes": len(preview),
        "metrics": job.get("metrics"), "metadata": job.get("metadata"),
        "referenceImageMetrics": job.get("referenceImageMetrics"),
        "status": "succeeded", "verified": ["authenticated HTTP admission", "durable job", "GLB download", "PNG preview"],
    }
    (args.directory / (name + ".live.json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()

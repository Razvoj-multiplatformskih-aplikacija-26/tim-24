"""Hedrion Qwen-Image 2.1 Turbo on L40S, with pinned source and weights.

Deploy: python -m modal deploy services/gpu_worker/modal_qwen_image.py
Prepare CPU-cached weights: python -m modal run services/gpu_worker/modal_qwen_image.py::prepare
One billed benchmark: python -m modal run services/gpu_worker/modal_qwen_image.py::benchmark

The checkpoint uses the Qwen Research License (non-commercial research/evaluation).
This module exposes no public, unauthenticated generation endpoint. The private
Hedrion gateway looks up ``hedrion-qwen-image/generate`` using the Modal SDK.
"""

from __future__ import annotations

import base64
import io
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import modal

MODEL_ID = "Qwen/Qwen-Image-2.1-Turbo"
MODEL_REVISION = "fc13ba1986fcb905854dc8de2f52eee395f49b5b"
DIFFUSERS_REVISION = "43e30028af5120d8b0868cb6975b9fad39cc4fab"
MODEL_DIR = "/models/qwen-image-2.1-turbo"
GPU = "L40S"
GPU_USD_PER_SECOND = 0.000542
app = modal.App("hedrion-qwen-image")
volume = modal.Volume.from_name("hedrion-qwen-image-weights", create_if_missing=True)

download_image = modal.Image.debian_slim(python_version="3.11").pip_install(
    "huggingface-hub==2.4.0"
)
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("git", "libgl1", "libglib2.0-0")
    .pip_install(
        "torch==2.11.0", "torchvision==0.26.0",
        index_url="https://download.pytorch.org/whl/cu128",
    )
    .pip_install(
        "transformers==5.23.0", "accelerate==1.15.0", "Pillow==13.0.0",
        "huggingface-hub==2.4.0", "sentencepiece==0.2.1",
        f"git+https://github.com/huggingface/diffusers.git@{DIFFUSERS_REVISION}",
    )
    .env({"HF_HUB_DISABLE_TELEMETRY": "1", "TOKENIZERS_PARALLELISM": "false"})
)


@app.function(image=download_image, volumes={"/models": volume}, cpu=4,
              memory=16384, timeout=1800, max_containers=1)
def download_weights() -> dict:
    """Network download runs on CPU, never on a billed GPU container."""
    from huggingface_hub import snapshot_download

    started = time.monotonic()
    snapshot_download(
        MODEL_ID, revision=MODEL_REVISION, local_dir=MODEL_DIR,
        allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "*.tiktoken", "*.jinja", "LICENSE*"],
    )
    volume.commit()
    return {"modelId": MODEL_ID, "revision": MODEL_REVISION,
            "download_ms": round((time.monotonic() - started) * 1000)}


_pipeline = None


@app.function(image=image, gpu=GPU, cpu=4, memory=65536,
              volumes={"/models": volume}, timeout=900,
              min_containers=0, max_containers=1, scaledown_window=30,
              retries=0)
def generate(payload: dict) -> dict:
    """Generate one reference PNG; exact Turbo sampling sigmas load from weights."""
    started = time.monotonic()
    import torch
    from diffusers import QwenImage21Pipeline
    prompt = payload.get("sourcePrompt", "")
    if not isinstance(prompt, str) or not 3 <= len(prompt.strip()) <= 2000:
        raise ValueError("sourcePrompt must contain 3 to 2000 characters")
    seed = int(payload.get("seed", 42))
    width, height = int(payload.get("width", 1024)), int(payload.get("height", 1024))
    if width != 1024 or height != 1024:
        raise ValueError("This bounded L40S profile supports 1024x1024 reference images")
    global _pipeline
    load_started = time.monotonic()
    cold_model_load = _pipeline is None
    if cold_model_load:
        if not Path(MODEL_DIR, "model_index.json").is_file():
            raise RuntimeError("ModelWeightsMissing: run the CPU prepare entrypoint first")
        _pipeline = QwenImage21Pipeline.from_pretrained(
            MODEL_DIR, dtype=torch.bfloat16, local_files_only=True,
        ).to("cuda")
        _pipeline.set_progress_bar_config(disable=True)
    torch.cuda.synchronize()
    load_ms = round((time.monotonic() - load_started) * 1000)
    torch.cuda.reset_peak_memory_stats()
    inference_started = time.monotonic()
    with torch.inference_mode():
        result = _pipeline(
            prompt=prompt.strip(), width=width, height=height,
            output_resolution=1024, use_kv_cache=True,
            generator=torch.Generator("cpu").manual_seed(seed),
        ).images[0]
    torch.cuda.synchronize()
    inference_ms = round((time.monotonic() - inference_started) * 1000)
    output = io.BytesIO()
    result.save(output, format="PNG")
    png = output.getvalue()
    elapsed_ms = round((time.monotonic() - started) * 1000)
    return {
        "jobId": payload.get("jobId"), "provider": "qwen_image_21_turbo",
        "imageBase64": base64.b64encode(png).decode("ascii"),
        "imageMime": "image/png",
        "metadata": {"modelId": MODEL_ID, "modelRevision": MODEL_REVISION,
                     "diffusersRevision": DIFFUSERS_REVISION, "seed": seed,
                     "width": result.width, "height": result.height,
                     "steps": 8, "imageMode": result.mode, "demo": False,
                     "modalFunctionCallId": modal.current_function_call_id()},
        "metrics": {"inference_ms": inference_ms, "load_ms": load_ms,
                    "elapsed_ms": elapsed_ms, "cold_model_load": cold_model_load,
                    "peak_vram_mb": round(torch.cuda.max_memory_allocated() / 1024**2, 1),
                    "gpu_type": GPU, "gpu_name": torch.cuda.get_device_name(),
                    "output_size_bytes": len(png),
                    "gpu_compute_estimate_usd": round(elapsed_ms / 1000 * GPU_USD_PER_SECOND, 6),
                    "cost_source": "estimated runtime x published GPU rate; excludes idle, CPU, RAM and storage"},
    }


@app.local_entrypoint()
def prepare():
    print(json.dumps(download_weights.remote()))


@app.local_entrypoint()
def benchmark(output_dir: str = ".local/benchmarks/2026-11-14"):
    """One real image, retained locally for all three 3D benchmark inputs."""
    target = Path(output_dir)
    target.mkdir(parents=True, exist_ok=True)
    payload = {
        "jobId": "benchmark-qwen-owl-20261114", "seed": 42,
        "sourcePrompt": "A single whimsical brass clockwork owl figurine, complete object centered, three-quarter view, clear silhouette, realistic materials, plain white background, no text, no pedestal",
    }
    started = time.monotonic()
    started_at = datetime.now(timezone.utc).isoformat()
    try:
        call = generate.spawn(payload)
        result = call.get()
    except Exception as error:
        (target / "qwen-result.json").write_text(json.dumps({
            "provider": "qwen_image_21_turbo", "status": "failed",
            "errorType": type(error).__name__, "startedAt": started_at,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "client_elapsed_ms": round((time.monotonic() - started) * 1000),
        }, indent=2), encoding="utf-8")
        raise
    client_elapsed_ms = round((time.monotonic() - started) * 1000)
    png = base64.b64decode(result.pop("imageBase64"))
    temporary = target / "reference.png.tmp"
    temporary.write_bytes(png)
    temporary.replace(target / "reference.png")
    result["benchmark"] = {"prompt": payload["sourcePrompt"], "seed": 42,
                           "client_elapsed_ms": client_elapsed_ms,
                           "modalFunctionCallId": call.object_id,
                           "startedAt": started_at,
                           "finishedAt": datetime.now(timezone.utc).isoformat(),
                           "imagePath": str(target / "reference.png")}
    (target / "qwen-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))

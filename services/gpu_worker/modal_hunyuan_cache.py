"""CPU-only checkpoint preparation, independent of the CUDA image build.

Run once before the Hunyuan worker's first GPU call. The shared Volume also
allows the full worker's prepare_weights function to reuse these downloads.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import modal

app = modal.App("hedrion-hunyuan-cache")
weights = modal.Volume.from_name("hedrion-hunyuan21-weights", create_if_missing=True)
image = modal.Image.debian_slim(python_version="3.10").pip_install("huggingface-hub==0.30.2", "hf-xet==1.1.0").env({"HF_HOME": "/models/hf"})


@app.function(image=image, volumes={"/models": weights}, timeout=1800, cpu=4, memory=8192)
def prepare() -> dict:
    from huggingface_hub import snapshot_download
    from urllib.request import urlretrieve

    started = time.monotonic()
    model = snapshot_download("tencent/Hunyuan3D-2.1", revision="0b94677654c57bb9a6b6845cd7b704ccf551d327",
        allow_patterns=["hunyuan3d-dit-v2-1/*", "hunyuan3d-paintpbr-v2-1/*", "LICENSE", "Notice.txt"])
    dino = snapshot_download("facebook/dinov2-giant", revision="611a9d42f2335e0f921f1e313ad3c1b7178d206d",
        allow_patterns=["*.json", "*.safetensors", "*.bin"])
    Path("/models/hunyuan-path.txt").write_text(model)
    Path("/models/dino-path.txt").write_text(dino)
    esrgan = Path("/models/RealESRGAN_x4plus.pth")
    if not esrgan.exists():
        urlretrieve("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth", esrgan)
    rembg = Path("/models/rembg/u2net.onnx")
    rembg.parent.mkdir(parents=True, exist_ok=True)
    if not rembg.exists():
        urlretrieve("https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx", rembg)
    weights.commit()
    return {"provider": "hunyuan3d_21", "prepared": True, "cpu_download_ms": round((time.monotonic() - started) * 1000)}


@app.local_entrypoint()
def main():
    result = prepare.remote()
    target = Path(".local/benchmarks/2026-11-14")
    target.mkdir(parents=True, exist_ok=True)
    (target / "hunyuan_cache.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))

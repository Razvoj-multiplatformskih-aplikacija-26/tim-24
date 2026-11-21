"""TRELLIS.2 image-to-3D deployment, restricted to the user's L40S GPU.

Deploy: python -m modal deploy modal_trellis2.py
Prepare gated weights on CPU first: python -m modal run modal_trellis2.py::prepare
Benchmark: python -m modal run modal_trellis2.py --image ../../.local/benchmarks/2026-11-14/reference.png
The Modal Secret hedrion-huggingface must contain HF_TOKEN, with accepted DINOv3
and RMBG-2.0 access. No credentials are embedded in source or outputs.
"""

from __future__ import annotations

import base64
import io
import json
import os
from pathlib import Path
import time

import modal

TRELLIS_COMMIT = "75fbf0183001ed9876c8dbb35de6b68552ee08bd"
FLEXGEMM_COMMIT = "6dd94a859c26ee8246888502eada3dd8ad85532e"
CUMESH_COMMIT = "12289e1062f0603f2f0d0771b02e1395d247f26f"
NVDIFFREC_COMMIT = "b296927cc7fd01c2ac1087c8065c4d7248f72da4"
WEIGHTS_REVISION = "af44b45f2e35a493886929c6d786e563ec68364d"
DINO_REVISION = "ea8dc2863c51be0a264bab82070e3e8836b02d51"
RMBG_REVISION = "2fd7b4b0f2393ddb39a267fb62df6c010928a6c6"
SS_REVISION = "25e0d31ffbebe4b5a97464dd851910efc3002d96"

app = modal.App("hedrion-trellis2")
volume = modal.Volume.from_name("hedrion-trellis2-weights", create_if_missing=True)
secrets = [modal.Secret.from_name("hedrion-huggingface")]
cpu_image = modal.Image.debian_slim(python_version="3.10").pip_install("huggingface-hub==0.36.0")

# Extensions are compiled on build CPUs specifically for Ada sm_89. The build
# requests no GPU; all runtime GPU functions explicitly request L40S.
image = (
    modal.Image.from_registry("nvidia/cuda:12.4.1-devel-ubuntu22.04", add_python="3.10")
    .apt_install("git", "build-essential", "ninja-build", "libgl1", "libglib2.0-0", "libjpeg-dev", "libpng-dev", "libegl1", "libopengl0")
    .env({"TORCH_CUDA_ARCH_LIST": "8.9", "CUDA_HOME": "/usr/local/cuda", "MAX_JOBS": "4", "ATTN_BACKEND": "sdpa", "SPARSE_ATTN_BACKEND": "sdpa", "PYTHONPATH": "/opt/trellis2:/opt/hedrion", "HF_HOME": "/weights/hf", "OPENCV_IO_ENABLE_OPENEXR": "1", "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True"})
    .pip_install("setuptools==75.8.0", "wheel", "packaging", "ninja")
    .pip_install("torch==2.6.0", "torchvision==0.21.0", index_url="https://download.pytorch.org/whl/cu124")
    .pip_install("numpy==1.26.4", "Pillow==11.3.0", "transformers==4.57.3", "huggingface-hub==0.36.0", "imageio", "imageio-ffmpeg", "tqdm", "easydict", "opencv-python-headless", "trimesh", "tensorboard", "pandas", "lpips", "zstandard", "kornia", "timm", "scipy", "safetensors", "einops")
    .env({"CC": "gcc", "CXX": "g++", "LDSHARED": "g++ -shared"})
    .run_commands(
        f"git clone https://github.com/microsoft/TRELLIS.2.git /opt/trellis2 && cd /opt/trellis2 && git checkout {TRELLIS_COMMIT} && git submodule update --init --recursive",
        "pip install git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8",
        "pip install git+https://github.com/NVlabs/nvdiffrast.git@v0.4.0 --no-build-isolation",
        f"git clone https://github.com/JeffreyXiang/nvdiffrec.git /opt/nvdiffrec && cd /opt/nvdiffrec && git checkout {NVDIFFREC_COMMIT} && pip install . --no-build-isolation",
        f"git clone https://github.com/JeffreyXiang/FlexGEMM.git /opt/flexgemm && cd /opt/flexgemm && git checkout {FLEXGEMM_COMMIT} && pip install . --no-build-isolation",
        f"git clone https://github.com/JeffreyXiang/CuMesh.git /opt/cumesh && cd /opt/cumesh && git checkout {CUMESH_COMMIT} && git submodule update --init --recursive && pip install . --no-build-isolation",
        "cd /opt/trellis2/o-voxel && pip install . --no-build-isolation",
    )
    .pip_install("xformers==0.0.29.post3", index_url="https://download.pytorch.org/whl/cu124", extra_options="--no-deps")
    .env({"SPARSE_ATTN_BACKEND": "xformers"})
    .add_local_dir(Path(__file__).parent / "hedrion_worker", "/opt/hedrion/hedrion_worker", ignore=["__pycache__", "*.pyc"])
)


@app.function(image=cpu_image, volumes={"/weights": volume}, secrets=secrets, timeout=1800, memory=4096)
def download_weights() -> dict:
    from huggingface_hub import hf_hub_download, snapshot_download
    from huggingface_hub.errors import HfHubHTTPError

    root = Path("/weights")
    # Prepare the public checkpoints once on CPU while a gated access request is
    # under review. A missing gated checkpoint never allocates an inference GPU.
    snapshot_download("microsoft/TRELLIS.2-4B", revision=WEIGHTS_REVISION, local_dir=root / "trellis2")
    for suffix in ["json", "safetensors"]:
        hf_hub_download("microsoft/TRELLIS-image-large", f"ckpts/ss_dec_conv3d_16l8_fp16.{suffix}", revision=SS_REVISION, local_dir=root / "ss")
    for model, revision, target in [
        ("briaai/RMBG-2.0", RMBG_REVISION, "rmbg"),
        ("facebook/dinov3-vitl16-pretrain-lvd1689m", DINO_REVISION, "dinov3"),
    ]:
        try:
            snapshot_download(model, revision=revision, local_dir=root / target)
        except HfHubHTTPError as error:
            volume.commit()
            message = str(error)[:1800]
            return {"ready": False, "publicWeightsPrepared": True, "blockedModel": model, "httpStatus": error.response.status_code if error.response is not None else None, "reason": "access_awaiting_review" if "awaiting" in message.lower() else "gated_access_required", "message": message}
    config = json.loads((root / "trellis2/pipeline.json").read_text())
    args = config["args"]
    args["models"]["sparse_structure_decoder"] = "../ss/ckpts/ss_dec_conv3d_16l8_fp16"
    args["image_cond_model"]["args"]["model_name"] = "/weights/dinov3"
    args["rembg_model"]["args"]["model_name"] = "/weights/rmbg"
    args["low_vram"] = True
    (root / "trellis2/pipeline-local.json").write_text(json.dumps(config))
    (root / "READY").write_text(WEIGHTS_REVISION)
    volume.commit()
    return {"ready": True, "weightsRevision": WEIGHTS_REVISION}


_pipeline = None


@app.function(image=cpu_image, secrets=secrets, timeout=45, memory=256)
def check_access() -> dict:
    """Check the gated config only, without downloading weights or using GPU."""
    import requests
    from datetime import datetime, timezone

    model = "facebook/dinov3-vitl16-pretrain-lvd1689m"
    response = requests.get(
        f"https://huggingface.co/{model}/resolve/{DINO_REVISION}/config.json",
        headers={"Authorization": "Bearer " + os.environ["HF_TOKEN"]},
        timeout=20,
    )
    allowed = response.status_code == 200
    message = "Model configuration is accessible." if allowed else response.text[:1600]
    return {"ready": False, "publicWeightsPrepared": True, "blockedModel": None if allowed else model, "httpStatus": response.status_code, "reason": "access_granted" if allowed else "access_awaiting_review" if "awaiting" in message.lower() else "gated_access_required", "message": message, "gateAccessGranted": allowed, "checkedAt": datetime.now(timezone.utc).isoformat(), "checkKind": "authenticated_config_only", "gpuInferenceInvoked": False}


@app.function(image=image, volumes={"/weights": volume}, cpu=2, memory=8192, timeout=180)
def check_environment() -> dict:
    """Import validation on CPU prevents paying for missing Python packages."""
    import importlib
    import torch
    checks = {}
    for module in ("cumesh", "o_voxel", "xformers.ops", "flex_gemm"):
        try:
            importlib.import_module(module)
            checks[module] = "imported"
        except RuntimeError as error:
            if "active drivers" not in str(error):
                raise
            checks[module] = "requires_gpu_driver"
    return {"imports": checks, "torch": torch.__version__, "weightsReady": Path("/weights/READY").exists(), "gpuRequested": "L40S", "gpuRuntimeVerified": False}


@app.function(image=image, gpu="L40S", volumes={"/weights": volume}, secrets=secrets, cpu=4, memory=65536, timeout=1200, min_containers=0, max_containers=1, scaledown_window=30)
def generate(payload: dict) -> dict:
    import tempfile
    import torch
    from PIL import Image
    from hedrion_worker.provider import GenerationInput, GenerationOutput, validate_glb

    started = time.monotonic()
    request = GenerationInput.from_json(payload)
    if request.input_type != "image_to_3d":
        raise ValueError("TRELLIS.2 expects an image; text is composed with the Qwen stage by the gateway")
    if not Path("/weights/READY").exists():
        raise RuntimeError("TRELLIS.2 weights are not prepared. Run the CPU prepare command with accepted HF access.")
    global _pipeline
    cold = _pipeline is None
    load_started = time.monotonic()
    if cold:
        from trellis2.pipelines import Trellis2ImageTo3DPipeline
        _pipeline = Trellis2ImageTo3DPipeline.from_pretrained("/weights/trellis2", config_file="pipeline-local.json")
        _pipeline.cuda()
    load_ms = round((time.monotonic() - load_started) * 1000)
    torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats()
    source = Image.open(io.BytesIO(request.source_image))
    # Some image generators return RGBA with a nearly opaque alpha channel.
    # That is not a foreground mask; let the actual segmentation model remove
    # the white backdrop instead of reconstructing it as geometry.
    if source.mode == "RGBA":
        transparent_pixels = sum(source.getchannel("A").histogram()[:16])
        if transparent_pixels < source.width * source.height * 0.01:
            source = source.convert("RGB")
    resolution = str(payload.get("resolution", "512"))
    if resolution not in ("512", "1024"):
        raise ValueError("Supported TRELLIS.2 resolutions are 512 and 1024")
    inference_started = time.monotonic()
    mesh = _pipeline.run(source, seed=int(payload.get("seed", 42)), pipeline_type="512" if resolution == "512" else "1024_cascade")[0]
    torch.cuda.synchronize()
    inference_ms = round((time.monotonic() - inference_started) * 1000)
    post_started = time.monotonic()
    mesh.simplify(16777216)
    from trellis2.utils import render_utils
    from trellis2.renderers import EnvMap
    import cv2
    from PIL import Image
    lighting = cv2.cvtColor(cv2.imread("/opt/trellis2/assets/hdri/forest.exr", cv2.IMREAD_UNCHANGED), cv2.COLOR_BGR2RGB)
    envmap = EnvMap(torch.tensor(lighting, dtype=torch.float32, device="cuda"))
    frames = render_utils.render_snapshot(mesh, resolution=512, r=2, fov=36, nviews=1, envmap=envmap)
    preview = io.BytesIO()
    Image.fromarray(frames["base_color"][0]).save(preview, format="PNG")
    import o_voxel
    glb = o_voxel.postprocess.to_glb(vertices=mesh.vertices, faces=mesh.faces, attr_volume=mesh.attrs, coords=mesh.coords, attr_layout=mesh.layout, voxel_size=mesh.voxel_size, aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]], decimation_target=50000, texture_size=1024, remesh=True, remesh_band=1, remesh_project=0, verbose=False)
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "model.glb"
        glb.export(str(out))
        model = out.read_bytes()
    validate_glb(model)
    torch.cuda.synchronize()
    elapsed = time.monotonic() - started
    return GenerationOutput(request.job_id, "trellis2", model, preview.getvalue(), {"demo": False, "model": "microsoft/TRELLIS.2-4B", "weightsRevision": WEIGHTS_REVISION, "codeRevision": TRELLIS_COMMIT, "previewKind": "generated_model_base_color", "previewIsGeneratedModel": True, "resolution": int(resolution), "triangleCount": len(glb.faces), "vertexCount": len(glb.vertices)}, {"load_ms": load_ms, "cold_start": cold, "inference_ms": inference_ms, "postprocess_ms": round((time.monotonic()-post_started)*1000), "worker_elapsed_ms": round(elapsed*1000), "peak_vram_mb": round(torch.cuda.max_memory_allocated()/1024**2, 1), "gpu_type": torch.cuda.get_device_name(0), "gpu_requested": "L40S", "estimated_gpu_usd": round(elapsed*0.000542, 6), "cost_is_estimate": True, "output_size_bytes": len(model)}).to_json()


@app.local_entrypoint()
def prepare():
    print(json.dumps(download_weights.remote()))


@app.local_entrypoint()
def main(image: str, output_dir: str = "../../.local/benchmarks/2026-11-14"):
    target = Path(output_dir)
    target.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = generate.remote({"jobId": "benchmark_trellis2_20261114", "ownerId": "benchmark", "inputType": "image_to_3d", "sourceImageBase64": base64.b64encode(Path(image).read_bytes()).decode(), "seed": 42, "resolution": "512"})
    (target / "trellis2.glb").write_bytes(base64.b64decode(result.pop("modelBase64")))
    (target / "trellis2-preview.png").write_bytes(base64.b64decode(result.pop("previewBase64")))
    result["metrics"]["client_elapsed_ms"] = round((time.monotonic()-started)*1000)
    (target / "trellis2-metrics.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))

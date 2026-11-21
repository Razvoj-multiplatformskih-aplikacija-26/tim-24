"""SPAR3D on Modal L4, with pinned upstream code and cached model weights.

Set HEDRION_HF_SECRET=hedrion-huggingface when deploying/download-preparing
after accepting the official gated model's terms on Hugging Face. That Modal
Secret must contain HF_TOKEN. No token is required by the GPU inference when
the pinned weights are already in the persistent volume.

  python -m modal deploy modal_spar3d.py
  python -m modal run modal_spar3d.py --prepare-only
  python -m modal run modal_spar3d.py --image ../../.local/benchmarks/2026-11-14/reference.png
"""

from __future__ import annotations

import base64
import io
import json
import os
import time
from pathlib import Path

import modal

UPSTREAM_REVISION = "fdc311b16809e6a8adc2f5a3407ebb3db1a95bd1"
MODEL_ID = "stabilityai/stable-point-aware-3d"
MODEL_REVISION = "5699918cb34f55cd7d828493d2725f3038313761"
DINO_REVISION = "47b73eefe95e8d44ec3623f8890bd894b6ea2d6c"
MODEL_PATH = f"/models/spar3d/{MODEL_REVISION}"
GPU = "L4"
GPU_USD_PER_SECOND = 0.80 / 3600  # Modal account L4 rate, checked 2026-11-14

app = modal.App("hedrion-spar3d")
weights = modal.Volume.from_name("hedrion-spar3d-weights", create_if_missing=True)
secret_name = os.environ.get("HEDRION_HF_SECRET", "hedrion-huggingface")
# Keep the dependency graph identical when this module is imported remotely.
download_secrets = [modal.Secret.from_name(secret_name)]

download_image = modal.Image.debian_slim(python_version="3.11").pip_install(
    "huggingface-hub==0.23.4", "transformers==4.42.3"
)

image = (
    modal.Image.from_registry("nvidia/cuda:12.4.1-devel-ubuntu22.04", add_python="3.11")
    .apt_install("git", "build-essential", "libgl1", "libglib2.0-0", "libegl1", "libgles2")
    .env({"TORCH_CUDA_ARCH_LIST": "8.9", "USE_CUDA": "1", "USE_NATIVE_ARCH": "0", "MAX_JOBS": "4", "HF_HOME": "/models/huggingface", "PYOPENGL_PLATFORM": "egl"})
    .pip_install("torch==2.5.1", "torchvision==0.20.1", index_url="https://download.pytorch.org/whl/cu124")
    .pip_install("setuptools==75.6.0", "wheel==0.45.1", "ninja==1.11.1.3", "numpy==1.26.4")
    .run_commands(
        "git clone https://github.com/Stability-AI/stable-point-aware-3d.git /opt/spar3d && cd /opt/spar3d && git checkout " + UPSTREAM_REVISION,
    )
    .pip_install("einops==0.7.0", "jaxtyping==0.2.31", "omegaconf==2.3.0", "transformers==4.42.3", "loralib==0.1.2", "trimesh==4.4.1", "huggingface-hub==0.23.4", "transparent-background==1.3.3", "safetensors==0.4.5", "pyrender==0.1.45")
    .pip_install("git+https://github.com/openai/CLIP.git@d05afc436d78f1c48dc0dbf8e5980a9d471f35f6", "git+https://github.com/SunzeY/AlphaCLIP.git@ef9262bc539728bf8ef2dfe9c402ae12bbfcd9ff", extra_options="--no-build-isolation")
    .env({"CC": "gcc", "CXX": "g++", "LDSHARED": "g++ -shared"})
    .run_commands("cd /opt/spar3d && pip install --no-build-isolation ./texture_baker ./uv_unwrapper")
    .apt_install("libosmesa6")
    .pip_install("PyOpenGL==3.1.7", extra_options="--no-deps")
    # transparent-background 1.3.3 imports its legacy GUI even in server mode.
    .pip_install("flet==0.24.1")
    .apt_install("libxrender1", "libxi6", "libxrandr2", "libxcursor1", "libxinerama1", "libglu1-mesa")
    .pip_install("pyglet==1.5.27")
    .env({"PYTHONPATH": "/opt/spar3d:/opt/hedrion", "ALPHA_CLIP_PATH": "/models/clip", "PYOPENGL_PLATFORM": "osmesa", "TRANSPARENT_BACKGROUND_FILE_PATH": "/models/background"})
    .add_local_dir(Path(__file__).parent / "hedrion_worker", "/opt/hedrion/hedrion_worker", ignore=["__pycache__", "*.pyc"])
)


@app.function(image=download_image, volumes={"/models": weights}, secrets=download_secrets, timeout=900, memory=8192, cpu=2)
def prepare() -> dict:
    """CPU-only: authenticate/download before allocating any billed GPU."""
    from huggingface_hub import snapshot_download
    from huggingface_hub.utils import GatedRepoError
    import hashlib
    import urllib.request
    import yaml

    started = time.monotonic()
    try:
        snapshot_download(MODEL_ID, revision=MODEL_REVISION, local_dir=MODEL_PATH, allow_patterns=["config.yaml", "model.safetensors", "LICENSE.md"])
        # The image tokenizer loads the public DINO model during initialization.
        dino_path = snapshot_download("facebook/dinov2-large", revision=DINO_REVISION, cache_dir="/models/huggingface/hub", allow_patterns=["config.json", "model.safetensors"])
    except GatedRepoError as exc:
        raise RuntimeError("SPAR3D access required: accept stabilityai/stable-point-aware-3d terms and deploy with HEDRION_HF_SECRET=hedrion-huggingface containing HF_TOKEN") from exc
    config = yaml.safe_load(Path(MODEL_PATH, "config.yaml").read_text())
    for component in ("image_tokenizer", "pdiff_image_tokenizer"):
        config.setdefault(component, {})["pretrained_model_name_or_path"] = dino_path
    Path(MODEL_PATH, "runtime-config.yaml").write_text(yaml.safe_dump(config))
    clip_name = config.get("image_estimator", {}).get("model", "ViT-L/14@336px")
    clip_models = {
        "ViT-L/14": ("b8cca3fd41ae0c99ba7e8951adf17d267cdb84cd88be6f7c2e0eca1737a03836", "ViT-L-14.pt"),
        "ViT-L/14@336px": ("3035c92b350959924f9f00213499208652fc7ea050643e8b385c2dac08641f02", "ViT-L-14-336px.pt"),
    }
    if clip_name not in clip_models:
        raise RuntimeError("Pinned SPAR3D config requests an unsupported CLIP backbone")
    digest, filename = clip_models[clip_name]
    clip_path = Path("/models/clip", filename)
    clip_path.parent.mkdir(parents=True, exist_ok=True)
    valid_clip = False
    if clip_path.is_file():
        with clip_path.open("rb") as stream:
            valid_clip = hashlib.file_digest(stream, "sha256").hexdigest() == digest
    if not valid_clip:
        urllib.request.urlretrieve(f"https://openaipublic.azureedge.net/clip/models/{digest}/{filename}", clip_path)
        with clip_path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                raise RuntimeError("CLIP checksum mismatch")
    Path(MODEL_PATH, "prepared.json").write_text(json.dumps({"model": MODEL_REVISION, "dino": DINO_REVISION, "clip": digest}))
    weights.commit()
    return {"model": MODEL_ID, "revision": MODEL_REVISION, "prepare_ms": round((time.monotonic() - started) * 1000)}


_state = None


def _needs_background_removal(source) -> bool:
    alpha = source.getchannel("A")
    return sum(alpha.histogram()[:16]) < source.width * source.height * 0.01


def _mask_metadata(source) -> dict:
    alpha = source.getchannel("A")
    histogram = alpha.histogram()
    pixels = source.width * source.height
    return {"alphaRange": list(alpha.getextrema()), "transparentFraction": sum(histogram[:16]) / pixels,
            "foregroundFraction": sum(histogram[128:]) / pixels,
            "foregroundBounds": alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()}


@app.function(image=image, volumes={"/models": weights}, timeout=300, memory=8192, cpu=4, scaledown_window=2, max_containers=1)
def check_reference(payload: dict) -> dict:
    """CPU-only segmentation QA/cache preparation before a paid 3D inference."""
    from PIL import Image
    from spar3d.utils import remove_background
    from transparent_background import Remover
    from hedrion_worker.provider import GenerationInput

    started = time.monotonic()
    request = GenerationInput.from_json(payload)
    with Image.open(io.BytesIO(request.source_image)) as original:
        original.load()
        source = original.convert("RGBA")
    before = _mask_metadata(source)
    needs_removal = _needs_background_removal(source)
    if needs_removal:
        source = remove_background(source, Remover(device="cpu"), force=True)
    after = _mask_metadata(source)
    if after["transparentFraction"] < 0.01 or not 0.003 < after["foregroundFraction"] < 0.99:
        raise ValueError("Reference segmentation did not isolate a foreground object")
    weights.commit()
    output = io.BytesIO()
    source.save(output, format="PNG")
    return {"sourceImageBase64": base64.b64encode(output.getvalue()).decode(), "backgroundRemoved": needs_removal,
            "before": before, "after": after, "cpu_elapsed_ms": round((time.monotonic() - started) * 1000)}


@app.function(image=download_image, volumes={"/models": weights}, timeout=30)
def readiness() -> dict:
    ready = all(Path(MODEL_PATH, name).is_file() for name in ("runtime-config.yaml", "model.safetensors", "prepared.json"))
    return {"provider": "spar3d", "gpu": GPU, "available": ready, "modelRevision": MODEL_REVISION, "reason": None if ready else "weightsNotPrepared"}


def _render_preview(mesh, reference, *, strict=False):
    """Render the generated mesh through headless Mesa; label any fallback."""
    from PIL import Image, ImageDraw
    try:
        import numpy as np
        import pyglet
        pyglet.options["shadow_window"] = False
        import pyrender
        import trimesh

        render_mesh = mesh.copy()
        render_mesh.apply_translation(-render_mesh.bounding_box.centroid)
        render_mesh.apply_scale(1.8 / max(render_mesh.extents))
        scene = pyrender.Scene(bg_color=[0.06, 0.07, 0.08, 1.0], ambient_light=[0.4, 0.4, 0.4])
        scene.add(pyrender.Mesh.from_trimesh(render_mesh, smooth=False))
        # Trimesh's camera transform looks at the origin with +Z away from it.
        # Upstream SPAR3D export faces -Z after its documented output rotations.
        pose = trimesh.transformations.euler_matrix(np.radians(-12), np.radians(205), 0)
        pose[:3, 3] = pose[:3, :3] @ np.array([0.0, 0.0, 3.0])
        scene.add(pyrender.PerspectiveCamera(yfov=np.pi / 3), pose=pose)
        scene.add(pyrender.DirectionalLight(color=np.ones(3), intensity=3.0), pose=pose)
        renderer = pyrender.OffscreenRenderer(640, 640)
        try:
            color, _ = renderer.render(scene)
        finally:
            renderer.delete()
        return Image.fromarray(color), {"previewKind": "rendered_model", "previewIsGeneratedModel": True}
    except Exception as exc:
        if strict:
            raise
        # Never imply a reference image is the generated model's render.
        preview = reference.convert("RGB").resize((640, 640))
        ImageDraw.Draw(preview).rectangle((0, 602, 640, 640), fill="black")
        ImageDraw.Draw(preview).text((12, 614), "Reference image - 3D render unavailable", fill="white")
        return preview, {"previewKind": "reference_image_fallback", "previewIsGeneratedModel": False, "previewFailure": type(exc).__name__}


@app.function(image=image, timeout=180, memory=8192, cpu=2, scaledown_window=2, max_containers=1)
def probe_environment() -> dict:
    """CPU-only native-import/render check, deliberately does not load AI weights."""
    import torch
    import trimesh
    from PIL import Image
    from spar3d.system import SPAR3D  # noqa: F401
    import alpha_clip  # noqa: F401
    from spar3d.models.tokenizers.image import DINOV2SingleImageTokenizer  # noqa: F401
    from spar3d.models.image_estimator.clip_based_estimator import ClipBasedHeadEstimator  # noqa: F401

    preview, metadata = _render_preview(trimesh.creation.icosphere(subdivisions=1), Image.new("RGB", (640, 640), "white"), strict=True)
    return {"torch": torch.__version__, "cudaAllocated": False, "previewSize": list(preview.size), **metadata}


@app.function(image=image, timeout=180, memory=8192, cpu=2, scaledown_window=2, max_containers=1)
def render_existing(model_base64: str) -> dict:
    """CPU render of an already generated GLB; does not rerun AI inference."""
    import trimesh
    from PIL import Image
    from hedrion_worker.provider import validate_glb

    data = base64.b64decode(model_base64, validate=True)
    validate_glb(data)
    model = trimesh.load(io.BytesIO(data), file_type="glb", force="mesh", process=False)
    preview, metadata = _render_preview(model, Image.new("RGB", (640, 640)), strict=True)
    output = io.BytesIO()
    preview.save(output, format="PNG")
    return {"previewBase64": base64.b64encode(output.getvalue()).decode(), **metadata}


@app.function(image=image, gpu=GPU, volumes={"/models": weights}, min_containers=0, max_containers=1, scaledown_window=30, timeout=600, memory=24576, cpu=4)
def generate(payload: dict) -> dict:
    """The private gateway invokes this function; clients never receive Modal credentials."""
    global _state
    started = time.monotonic()
    import torch
    from PIL import Image
    from spar3d.system import SPAR3D
    from spar3d.utils import foreground_crop, remove_background
    from transparent_background import Remover
    from hedrion_worker.provider import GenerationInput, GenerationOutput, validate_glb

    request = GenerationInput.from_json(payload)
    if request.input_type != "image_to_3d":
        raise ValueError("SPAR3D requires an image; the gateway must run text-to-image first")
    if not Path(MODEL_PATH, "model.safetensors").is_file():
        raise RuntimeError("SPAR3D weights not prepared: run the CPU prepare function before inference")
    load_started = time.monotonic()
    cold = _state is None
    if cold:
        model = SPAR3D.from_pretrained(MODEL_PATH, config_name="runtime-config.yaml", weight_name="model.safetensors", low_vram_mode=False).to("cuda").eval()
        _state = (model, None)
    model, remover = _state
    load_ms = round((time.monotonic() - load_started) * 1000)
    preprocess_started = time.monotonic()
    with Image.open(io.BytesIO(request.source_image)) as original:
        original.load()
        source = original.convert("RGBA")
    source_mask_before = _mask_metadata(source)
    background_removed = _needs_background_removal(source)
    if background_removed:
        if remover is None:
            remover = Remover(device="cuda")
            _state = (model, remover)
        source = remove_background(source, remover, force=True)
    source_mask_after = _mask_metadata(source)
    if source_mask_after["transparentFraction"] < 0.01 or not 0.003 < source_mask_after["foregroundFraction"] < 0.99:
        raise ValueError("Reference segmentation did not isolate a foreground object")
    source = foreground_crop(source, crop_ratio=1.3)
    preprocess_ms = round((time.monotonic() - preprocess_started) * 1000)
    seed = int(payload.get("seed", 42)) & 0x7fffffff
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.cuda.reset_peak_memory_stats()
    torch.cuda.synchronize()
    inference_started = time.monotonic()
    with torch.inference_mode(), torch.autocast(device_type="cuda", dtype=torch.bfloat16):
        mesh, _ = model.run_image(source, bake_resolution=1024, remesh="none", vertex_count=-1, return_points=False)
    torch.cuda.synchronize()
    inference_ms = round((time.monotonic() - inference_started) * 1000)
    peak_mb = round(torch.cuda.max_memory_allocated() / 1024**2, 2)
    postprocess_started = time.monotonic()
    model_bytes = mesh.export(file_type="glb", include_normals=True)
    validate_glb(model_bytes)
    preview, preview_metadata = _render_preview(mesh, source)
    preview_buffer = io.BytesIO()
    preview.save(preview_buffer, format="PNG")
    elapsed_ms = round((time.monotonic() - started) * 1000)
    return GenerationOutput(request.job_id, "spar3d", model_bytes, preview_buffer.getvalue(),
        {"demo": False, "modelId": MODEL_ID, "modelRevision": MODEL_REVISION, "codeRevision": UPSTREAM_REVISION, "seed": seed, "triangleCount": len(mesh.faces), "vertexCount": len(mesh.vertices), "backgroundRemoved": background_removed, "sourceMaskBefore": source_mask_before, "sourceMaskAfter": source_mask_after, **preview_metadata},
        {"gpu_type": GPU, "gpu_device": torch.cuda.get_device_name(), "cpu_cores_requested": 4, "memory_mib_requested": 24576, "cold_start": cold, "load_ms": load_ms, "preprocess_ms": preprocess_ms, "inference_ms": inference_ms, "postprocess_ms": round((time.monotonic() - postprocess_started) * 1000), "worker_elapsed_ms": elapsed_ms, "peak_vram_mb": peak_mb, "output_size_bytes": len(model_bytes), "gpu_compute_estimate_usd": round(elapsed_ms / 1000 * GPU_USD_PER_SECOND, 6), "cost_kind": "GPU-only estimate; excludes startup, idle, CPU, RAM, storage; not billed credits"}).to_json()


@app.local_entrypoint()
def benchmark(image: str = "", output: str = "", prepare_only: bool = False):
    prepared = prepare.remote()
    print(json.dumps(prepared))
    if prepare_only:
        return
    local_benchmark_path = Path(__file__).resolve().parents[2] / ".local" / "benchmarks" / "2026-11-14"
    target = Path(output) if output else local_benchmark_path
    target.mkdir(parents=True, exist_ok=True)
    source_path = Path(image) if image else local_benchmark_path / "reference.png"
    payload = {"jobId": "benchmark_spar3d_20261114", "ownerId": "benchmark", "inputType": "image_to_3d", "sourceImageBase64": base64.b64encode(source_path.read_bytes()).decode(), "seed": 42}
    started = time.monotonic()
    call = generate.spawn(payload)
    result = call.get()
    wall_ms = round((time.monotonic() - started) * 1000)
    (target / "spar3d.glb").write_bytes(base64.b64decode(result.pop("modelBase64")))
    (target / "spar3d.png").write_bytes(base64.b64decode(result.pop("previewBase64")))
    result["metrics"].update({"client_wall_ms": wall_ms, "modal_call_id": call.object_id, "prepare": prepared})
    (target / "spar3d.metrics.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))

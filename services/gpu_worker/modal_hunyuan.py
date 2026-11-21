"""Hedrion's pinned Hunyuan3D 2.1 shape + PBR worker on Modal L40S.

Deploy: python -m modal deploy services/gpu_worker/modal_hunyuan.py
Prepare weights without renting a GPU: modal run ... --prepare
The public application calls the authenticated Hedrion dispatcher, never this
function directly. Published upstream license/NOTICE remain in the image.
"""

from __future__ import annotations

import base64
import io
import json
import math
import os
import sys
import tempfile
import time
from pathlib import Path

import modal

UPSTREAM_COMMIT = "82920d643c0dc2f7bfd7255f45f62d386edfe60c"
WEIGHTS_REVISION = "0b94677654c57bb9a6b6845cd7b704ccf551d327"
DINO_REVISION = "611a9d42f2335e0f921f1e313ad3c1b7178d206d"
ROOT = "/opt/Hunyuan3D-2.1"
app = modal.App("hedrion-hunyuan3d")
weights = modal.Volume.from_name("hedrion-hunyuan21-weights", create_if_missing=True)

image = (
    modal.Image.from_registry("nvidia/cuda:12.4.1-devel-ubuntu22.04", add_python="3.11")
    .apt_install(
        "git", "build-essential", "cmake", "ninja-build", "libegl1-mesa-dev",
        "libgl1", "libglib2.0-0", "libxrender1", "libsm6", "libxext6",
        "libxi6", "libxkbcommon-x11-0", "libeigen3-dev", "libcgal-dev",
    )
    .env({
        "HF_HOME": "/models/hf", "U2NET_HOME": "/models/rembg",
        "TORCH_CUDA_ARCH_LIST": "8.9", "CUDA_HOME": "/usr/local/cuda",
        "PYOPENGL_PLATFORM": "egl", "OMP_NUM_THREADS": "4",
        "PYTHONPATH": ROOT + "/hy3dshape:" + ROOT + "/hy3dpaint:/opt/hedrion",
        "HF_HUB_DISABLE_TELEMETRY": "1",
    })
    .pip_install("pip==25.0.1", "setuptools==75.8.0", "wheel==0.45.1", "ninja==1.11.1.1", "pybind11==2.13.4")
    .pip_install("torch==2.5.1", "torchvision==0.20.1", "torchaudio==2.5.1", index_url="https://download.pytorch.org/whl/cu124")
    .run_commands(
        "git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git " + ROOT,
        "git -C " + ROOT + " checkout " + UPSTREAM_COMMIT,
        # Demo servers and deepspeed aren't required by inference. Keep the
        # upstream tested inference pins; install exclusively from PyPI.
        # Upstream's bpy==4.0 is no longer published on PyPI. Blender's 4.2.0
        # wheel uses Python 3.11 and retains the OBJ/glTF APIs needed here.
        "python -c \"from pathlib import Path; p=Path('" + ROOT + "/requirements.txt'); Path('/tmp/hunyuan-reqs.txt').write_text('\\n'.join('bpy==4.2.0' if l.startswith('bpy==') else l for l in p.read_text().splitlines() if not l.startswith('--') and not any(l.startswith(s) for s in ['gradio','fastapi','uvicorn','deepspeed','tb_nightly'])))\"",
        "pip install -r /tmp/hunyuan-reqs.txt",
    )
    .pip_install("numpy==1.24.4", "fast-simplification==0.1.7")
    # Modal's standalone CPython sysconfig names clang++; choose the installed
    # GNU toolchain explicitly for Python's native-extension linker as well.
    .env({"CC": "gcc", "CXX": "g++", "LDSHARED": "g++ -shared"})
    .run_commands(
        "cd " + ROOT + "/hy3dpaint/custom_rasterizer && pip install --no-build-isolation -e .",
        "cd " + ROOT + "/hy3dpaint/DifferentiableRenderer && bash compile_mesh_painter.sh",
        "python -c \"from pathlib import Path; p=Path('" + ROOT + "/hy3dpaint/utils/multiview_utils.py'); s=p.read_text(); old='repo_id=config.multiview_pretrained_path,'; assert old in s; p.write_text(s.replace(old, old+' revision=\\\"" + WEIGHTS_REVISION + "\\\",'))\"",
    )
    .add_local_dir(Path(__file__).parent / "hedrion_worker", "/opt/hedrion/hedrion_worker", ignore=["__pycache__", "*.pyc"])
)


@app.function(image=image, volumes={"/models": weights}, timeout=1800, cpu=4, memory=16384)
def prepare_weights() -> dict:
    """Download all checkpoints on a CPU container before the GPU is started."""
    from huggingface_hub import snapshot_download
    from urllib.request import urlretrieve

    started = time.monotonic()
    model_root = snapshot_download(
        "tencent/Hunyuan3D-2.1", revision=WEIGHTS_REVISION,
        allow_patterns=["hunyuan3d-dit-v2-1/*", "hunyuan3d-paintpbr-v2-1/*", "LICENSE", "Notice.txt"],
    )
    dino_root = snapshot_download("facebook/dinov2-giant", revision=DINO_REVISION, allow_patterns=["*.json", "*.safetensors", "*.bin"])
    Path("/models/hunyuan-path.txt").write_text(model_root)
    Path("/models/dino-path.txt").write_text(dino_root)
    esrgan = Path("/models/RealESRGAN_x4plus.pth")
    if not esrgan.exists():
        urlretrieve("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth", esrgan)
    from rembg import new_session
    new_session("u2net")
    weights.commit()
    return {"provider": "hunyuan3d_21", "prepared": True, "elapsed_ms": round((time.monotonic() - started) * 1000)}


_pipelines = None


@app.function(image=image, volumes={"/models": weights}, timeout=180, cpu=2, memory=8192)
def check_environment() -> dict:
    """Validate native extension imports and checkpoint paths without a GPU."""
    os.chdir(ROOT)
    import torch
    import torchvision.transforms._functional_tensor as functional_tensor
    sys.modules["torchvision.transforms.functional_tensor"] = functional_tensor
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
    from textureGenPipeline import Hunyuan3DPaintPipeline
    import custom_rasterizer
    import bpy
    import rembg
    import numpy
    return {"torch": torch.__version__, "blender": bpy.app.version_string,
            "numpy": numpy.__version__,
            "sourceCommit": UPSTREAM_COMMIT,
            "weightsPrepared": Path("/models/hunyuan-path.txt").exists(),
            "shapePipeline": Hunyuan3DDiTFlowMatchingPipeline.__name__,
            "paintPipeline": Hunyuan3DPaintPipeline.__name__}


def _load_pipelines():
    global _pipelines
    if _pipelines is not None:
        return _pipelines, 0
    import torch
    import torchvision.transforms._functional_tensor as functional_tensor
    # basicsr 1.4.2 imports the old torchvision module name.
    sys.modules["torchvision.transforms.functional_tensor"] = functional_tensor
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
    from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig

    started = time.monotonic()
    shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(Path("/models/hunyuan-path.txt").read_text())
    cfg = Hunyuan3DPaintConfig(max_num_view=6, resolution=512)
    cfg.realesrgan_ckpt_path = "/models/RealESRGAN_x4plus.pth"
    cfg.dino_ckpt_path = Path("/models/dino-path.txt").read_text()
    paint = Hunyuan3DPaintPipeline(cfg)
    torch.cuda.synchronize()
    _pipelines = (shape, paint)
    return _pipelines, round((time.monotonic() - started) * 1000)


def _render_preview(glb: Path, output: Path) -> bool:
    """Render the generated model itself with headless Blender CPU Cycles."""
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    scene = bpy.context.scene
    objects = [o for o in scene.objects if o.type == "MESH"]
    if not objects:
        return False
    points = [o.matrix_world @ Vector(corner) for o in objects for corner in o.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (low + high) / 2
    size = max((high - low).length, 0.1)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + Vector((1.5, -2.3, 1.3)) * size
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = size * 1.2
    scene.camera = camera
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.2, 0.22, 0.25, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    scene.world = world
    for index, position in enumerate(((2, -3, 4), (-3, -1, 2), (1, 3, 3))):
        light_data = bpy.data.lights.new("PreviewLight" + str(index), "AREA")
        light_data.energy = 700 * size * size
        light_data.shape = "DISK"
        light_data.size = size * 2
        light = bpy.data.objects.new(light_data.name, light_data)
        scene.collection.objects.link(light)
        light.location = center + Vector(position) * size
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return output.is_file()


def _needs_background_removal(source) -> bool:
    """Near-opaque generated RGBA isn't an already segmented object.

    Diffusion decoders can produce alpha248..255 for an opaque white background.
    Preserve genuine cutouts, but run segmentation unless at least 1% of pixels
    are effectively transparent. Testing only for alpha==255 creates a plane.
    """
    histogram = source.getchannel("A").histogram()
    transparent_pixels = sum(histogram[:16])
    return transparent_pixels < source.width * source.height * 0.01


@app.function(image=image, volumes={"/models": weights}, timeout=180, cpu=4, memory=8192)
def check_reference(image_base64: str) -> dict:
    """CPU-only visual preflight uses the same segmentation as real inference."""
    from PIL import Image
    from rembg import remove, new_session
    source = Image.open(io.BytesIO(base64.b64decode(image_base64))).convert("RGBA")
    needed = _needs_background_removal(source)
    if needed:
        source = remove(source, session=new_session("u2net"))
    buffer = io.BytesIO()
    source.save(buffer, format="PNG")
    histogram = source.getchannel("A").histogram()
    return {"backgroundRemoved": needed,
            "transparentFraction": sum(histogram[:16]) / (source.width * source.height),
            "imageBase64": base64.b64encode(buffer.getvalue()).decode()}


@app.function(image=image, gpu="L40S", volumes={"/models": weights}, min_containers=0,
              max_containers=1, scaledown_window=60, timeout=1200, cpu=8, memory=65536)
def generate(payload: dict) -> dict:
    started = time.monotonic()
    from PIL import Image, ImageDraw
    import torch
    import trimesh
    from rembg import remove, new_session
    from hedrion_worker.provider import GenerationInput, GenerationOutput, validate_glb

    request = GenerationInput.from_json(payload)
    if request.input_type != "image_to_3d":
        raise ValueError("Hunyuan3D requires the dispatcher's reference image stage")
    os.chdir(ROOT)
    torch.cuda.reset_peak_memory_stats()
    (shape, paint), load_ms = _load_pipelines()
    source = Image.open(io.BytesIO(request.source_image)).convert("RGBA")
    background_removed = _needs_background_removal(source)
    if background_removed:
        source = remove(source, session=new_session("u2net"))
    inference_started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="hedrion-hunyuan-") as folder:
        directory = Path(folder)
        image_path = directory / "source.png"
        source.save(image_path)
        shape_started = time.monotonic()
        mesh = shape(image=source, num_inference_steps=50, octree_resolution=384,
                     generator=torch.Generator(device="cuda").manual_seed(int(payload.get("seed", 42))))[0]
        torch.cuda.synchronize()
        shape_ms = round((time.monotonic() - shape_started) * 1000)
        white_path = directory / "shape.obj"
        mesh.export(white_path)
        texture_started = time.monotonic()
        paint(str(white_path), image_path=str(image_path), output_mesh_path=str(directory / "model.obj"))
        torch.cuda.synchronize()
        texture_ms = round((time.monotonic() - texture_started) * 1000)
        inference_ms = round((time.monotonic() - inference_started) * 1000)
        model_path = directory / "model.glb"
        model = model_path.read_bytes()
        validate_glb(model)
        scene = trimesh.load(model_path, force="scene")
        meshes = list(scene.geometry.values())
        render_started = time.monotonic()
        preview_path = directory / "preview.png"
        preview_kind = "generated_model_render"
        try:
            if not _render_preview(model_path, preview_path):
                raise RuntimeError("Empty preview")
        except Exception:
            preview_kind = "reference_image_fallback"
            fallback = source.convert("RGB").resize((512, 512))
            ImageDraw.Draw(fallback).text((12, 480), "Reference image - 3D render unavailable", fill="red")
            fallback.save(preview_path)
        preview = preview_path.read_bytes()
        render_ms = round((time.monotonic() - render_started) * 1000)
    elapsed_ms = round((time.monotonic() - started) * 1000)
    return GenerationOutput(
        request.job_id, "hunyuan3d_21", model, preview,
        {"demo": False, "model": "Hunyuan3D-2.1", "upstreamCommit": UPSTREAM_COMMIT,
         "weightsRevision": WEIGHTS_REVISION, "textured": True, "pbr": True,
         "backgroundRemoved": background_removed,
         "previewKind": preview_kind, "previewIsGeneratedModel": preview_kind == "generated_model_render",
         "triangleCount": sum(len(m.faces) for m in meshes), "vertexCount": sum(len(m.vertices) for m in meshes),
         "dimensions": scene.extents.tolist()},
        {"load_ms": load_ms, "shape_ms": shape_ms, "texture_ms": texture_ms,
         "inference_ms": inference_ms, "render_ms": render_ms, "elapsed_ms": elapsed_ms,
         "worker_elapsed_ms": elapsed_ms, "gpu_type": torch.cuda.get_device_name(0),
         "gpu_class": "L40S", "peak_vram_mb": round(torch.cuda.max_memory_allocated() / 1024 ** 2, 1),
         "vram_measurement": "torch.cuda.max_memory_allocated; excludes native CUDA allocations",
         "configured_cpu_cores": 8, "configured_memory_mib": 65536,
         "output_size_bytes": len(model), "preview_size_bytes": len(preview),
         "gpu_compute_estimate_usd": elapsed_ms / 1000 * 0.000542, "actual_billed_usd": None},
    ).to_json()


@app.local_entrypoint()
def main(prepare: bool = False, source: str = ".local/benchmarks/2026-11-14/reference.png"):
    if prepare:
        print(json.dumps(prepare_weights.remote()))
        return
    directory = Path(".local/benchmarks/2026-11-14")
    directory.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = generate.remote({
        "jobId": "benchmark_hunyuan21", "ownerId": "benchmark", "inputType": "image_to_3d", "seed": 42,
        "sourceImageBase64": base64.b64encode(Path(source).read_bytes()).decode(),
    })
    end_to_end_ms = round((time.monotonic() - started) * 1000)
    (directory / "hunyuan3d_21.glb").write_bytes(base64.b64decode(result.pop("modelBase64")))
    (directory / "hunyuan3d_21.png").write_bytes(base64.b64decode(result.pop("previewBase64")))
    result["metrics"]["client_end_to_end_ms"] = end_to_end_ms
    (directory / "hunyuan3d_21.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))

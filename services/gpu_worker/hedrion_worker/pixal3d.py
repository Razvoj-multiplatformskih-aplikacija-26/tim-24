"""Unselected experimental image-to-3D adapter retained for future evaluation.

This is not the product's selected model. It is CPU contract-tested with a
controlled CLI only. Actual GPU inference has not been tested. The normal
worker keeps this adapter disabled behind ENABLE_EXPERIMENTAL_PROVIDER.
"""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Mapping

from .provider import (
    MAX_RESULT_BYTES,
    GenerationInput,
    GenerationOutput,
    WorkerError,
    validate_glb,
    validate_image_header,
)


class Pixal3DCliProvider:
    name = "pixal3d"

    def __init__(
        self,
        root: Path,
        python_executable: Path | None = None,
        *,
        timeout_seconds: float = 900,
        low_vram: bool = True,
        resolution: int = 1024,
        gpu_type: str = "unmeasured",
    ):
        if not root.is_absolute() or not (root / "inference.py").is_file():
            raise ValueError("PIXAL3D_ROOT must be an absolute existing checkout containing inference.py")
        self.root = root.resolve(strict=True)
        self.python = python_executable or Path(sys.executable)
        if not self.python.is_absolute() or not self.python.is_file():
            raise ValueError("PIXAL3D_PYTHON must identify an existing absolute Python executable")
        if not 0 < timeout_seconds <= 1100:
            raise ValueError("PIXAL3D_TIMEOUT_SECONDS must be between 0 and 1100")
        if resolution not in (1024, 1536):
            raise ValueError("PIXAL3D_RESOLUTION must be 1024 or 1536")
        self.timeout_seconds = timeout_seconds
        self.low_vram = low_vram
        self.resolution = resolution
        self.gpu_type = gpu_type
        try:
            from PIL import Image  # noqa: F401
        except ImportError as exc:
            raise ValueError("Pixal3D worker requires Pillow in its active Python environment") from exc

    @classmethod
    def from_environment(cls, env: Mapping[str, str] | None = None) -> Pixal3DCliProvider:
        env = os.environ if env is None else env
        root = env.get("PIXAL3D_ROOT", "")
        if not root:
            raise ValueError("GENERATION_PROVIDER=pixal3d requires PIXAL3D_ROOT")
        low_vram = env.get("PIXAL3D_LOW_VRAM", "true").lower()
        if low_vram not in ("true", "false", "1", "0"):
            raise ValueError("PIXAL3D_LOW_VRAM must be true or false")
        try:
            timeout = float(env.get("PIXAL3D_TIMEOUT_SECONDS", "900"))
            resolution = int(env.get("PIXAL3D_RESOLUTION", "1024"))
        except ValueError as exc:
            raise ValueError("Invalid Pixal3D timeout or resolution configuration") from exc
        return cls(
            Path(root),
            Path(env["PIXAL3D_PYTHON"]) if env.get("PIXAL3D_PYTHON") else None,
            timeout_seconds=timeout,
            low_vram=low_vram in ("true", "1"),
            resolution=resolution,
            gpu_type=env.get("PIXAL3D_GPU", "unmeasured"),
        )

    def _reference(self, data: bytes) -> tuple[bytes, bytes]:
        """Fully decode input, strip metadata, then make an explicitly labeled fallback."""
        from PIL import Image, ImageDraw, ImageOps, UnidentifiedImageError

        validate_image_header(data)
        try:
            with Image.open(io.BytesIO(data)) as probe:
                if probe.format not in ("PNG", "JPEG"):
                    raise WorkerError("UnsupportedImageFormat")
                width, height = probe.size
                if not (1 <= width <= 8192 and 1 <= height <= 8192 and width * height <= 32_000_000):
                    raise WorkerError("InvalidImageDimensions")
                probe.verify()
            with Image.open(io.BytesIO(data)) as opened:
                opened.load()
                image = ImageOps.exif_transpose(opened).convert("RGBA")
                # A new image strips input EXIF, ICC profile and arbitrary text chunks.
                clean = Image.new("RGBA", image.size)
                clean.paste(image)
                source = io.BytesIO()
                clean.save(source, format="PNG")
                clean.thumbnail((768, 768))
                preview = Image.new("RGB", (max(clean.width, 360), clean.height + 48), (20, 26, 43))
                preview.paste(clean, ((preview.width - clean.width) // 2, 48), clean)
                draw = ImageDraw.Draw(preview)
                draw.text((10, 7), "REFERENTNA SLIKA", fill=(225, 191, 99))
                draw.text((10, 24), "3D pregled rezultata nije napravljen", fill=(225, 191, 99))
                preview_data = io.BytesIO()
                preview.save(preview_data, format="PNG")
                return source.getvalue(), preview_data.getvalue()
        except WorkerError:
            raise
        except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
            raise WorkerError("ImageDecodeFailed") from exc

    def generate(self, request: GenerationInput) -> GenerationOutput:
        if request.input_type != "image_to_3d":
            # Pixal3D is not a native text-to-3D model. No silent mock downgrade.
            raise WorkerError("UnsupportedInput")
        if request.source_image is None:
            raise WorkerError("SourceImageRequired")
        started = time.monotonic()
        source, preview = self._reference(request.source_image)
        preprocess_ms = round((time.monotonic() - started) * 1000)
        with tempfile.TemporaryDirectory(prefix="hedrion-inference-") as temporary:
            workspace = Path(temporary).resolve()
            source_path, output_path = workspace / "source.png", workspace / "output.glb"
            source_path.write_bytes(source)
            args = [
                str(self.python), str(self.root / "inference.py"),
                "--image", str(source_path), "--output", str(output_path),
                "--resolution", str(self.resolution),
            ]
            if self.low_vram:
                args.append("--low_vram")
            child_env = os.environ.copy()
            child_env.pop("WORKER_SHARED_SECRET", None)
            inference_started = time.monotonic()
            try:
                result = subprocess.run(
                    args,
                    cwd=self.root,
                    env=child_env,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=self.timeout_seconds,
                    check=False,
                    shell=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise WorkerError("InferenceTimeout", 504) from exc
            except OSError as exc:
                raise WorkerError("InferenceUnavailable", 503) from exc
            if result.returncode != 0:
                raise WorkerError("InferenceFailed", 502)
            inference_ms = round((time.monotonic() - inference_started) * 1000)
            postprocess_started = time.monotonic()
            if not output_path.is_file() or output_path.is_symlink():
                raise WorkerError("WorkerOutputMissing", 502)
            if output_path.resolve().parent != workspace:
                raise WorkerError("InvalidOutputPath", 502)
            size = output_path.stat().st_size
            if not 28 <= size <= MAX_RESULT_BYTES:
                raise WorkerError("InvalidGlbSize", 502)
            model = output_path.read_bytes()
            document = validate_glb(model)
        metadata: dict[str, Any] = {
            "demo": False,
            "sha256": hashlib.sha256(model).hexdigest(),
            "previewKind": "reference_image_fallback",
            "previewIsGeneratedModel": False,
            "previewWarning": "Referentna slika; 3D pregled rezultata nije napravljen.",
            "materialCount": len(document.get("materials", [])),
            "textureCount": len(document.get("textures", [])),
        }
        accessors = document.get("accessors", [])
        triangles = vertices = 0
        for mesh in document.get("meshes", []):
            for primitive in mesh.get("primitives", []):
                position = primitive.get("attributes", {}).get("POSITION")
                if isinstance(position, int) and 0 <= position < len(accessors):
                    vertices += accessors[position].get("count", 0)
                index = primitive.get("indices")
                if primitive.get("mode", 4) == 4 and isinstance(index, int) and 0 <= index < len(accessors):
                    triangles += accessors[index].get("count", 0) // 3
        metadata.update({"triangleCount": triangles, "vertexCount": vertices})
        return GenerationOutput(
            request.job_id, self.name, model, preview, metadata,
            {"inference_ms": inference_ms,
             "preprocess_ms": preprocess_ms,
             "postprocess_ms": round((time.monotonic() - postprocess_started) * 1000),
             "worker_elapsed_ms": round((time.monotonic() - started) * 1000),
             "output_size_bytes": len(model), "preview_size_bytes": len(preview),
             "gpu_type": self.gpu_type, "gpu_type_source": "deployment_configuration",
             "resolution": self.resolution, "low_vram": self.low_vram,
             "cold_start_ms": None, "peak_vram_mb": None, "cost": None},
        )

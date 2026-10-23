"""Provider contract, deterministic demo geometry, and bounded GLB validation."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import math
import re
import struct
import time
import zlib
from dataclasses import dataclass
from typing import Any, Protocol

MAX_IMAGE_BYTES = 10_000_000
MAX_RESULT_BYTES = 200_000_000
_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


class WorkerError(Exception):
    def __init__(self, code: str, status: int = 422):
        super().__init__(code)
        self.code = code
        self.status = status


@dataclass(frozen=True)
class GenerationInput:
    job_id: str
    owner_id: str
    input_type: str
    source_image: bytes | None = None
    source_prompt: str | None = None

    @classmethod
    def from_json(cls, data: Any) -> GenerationInput:
        if not isinstance(data, dict):
            raise WorkerError("InvalidInput", 400)
        job_id, owner_id = data.get("jobId"), data.get("ownerId")
        if any(not isinstance(v, str) or not _ID.fullmatch(v) for v in (job_id, owner_id)):
            raise WorkerError("InvalidIdentifier")
        input_type = data.get("inputType", "image_to_3d")
        if input_type not in ("image_to_3d", "text_to_3d"):
            raise WorkerError("UnsupportedInputType")
        prompt = data.get("sourcePrompt")
        if prompt is not None and (not isinstance(prompt, str) or len(prompt) > 2000):
            raise WorkerError("InvalidPrompt")
        image = None
        if data.get("sourceImageBase64") is not None:
            raw = data["sourceImageBase64"]
            if not isinstance(raw, str) or len(raw) > (MAX_IMAGE_BYTES + 2) // 3 * 4:
                raise WorkerError("ImageTooLarge")
            try:
                image = base64.b64decode(raw, validate=True)
            except (ValueError, binascii.Error) as exc:
                raise WorkerError("InvalidImage") from exc
            validate_image_header(image)
        if input_type == "image_to_3d" and image is None:
            raise WorkerError("SourceImageRequired")
        if input_type == "text_to_3d" and (prompt is None or not prompt.strip()):
            raise WorkerError("SourcePromptRequired")
        return cls(job_id, owner_id, input_type, image, prompt)


@dataclass(frozen=True)
class GenerationOutput:
    job_id: str
    provider: str
    model: bytes
    preview: bytes
    metadata: dict[str, Any]
    metrics: dict[str, Any]

    def to_json(self) -> dict[str, Any]:
        return {
            "jobId": self.job_id,
            "provider": self.provider,
            "modelBase64": base64.b64encode(self.model).decode("ascii"),
            "previewBase64": base64.b64encode(self.preview).decode("ascii"),
            "modelMime": "model/gltf-binary",
            "previewMime": "image/png",
            "metadata": self.metadata,
            "metrics": self.metrics,
        }


class GenerationProvider(Protocol):
    name: str

    def generate(self, request: GenerationInput) -> GenerationOutput: ...


def validate_image_header(data: bytes) -> None:
    """Cheap preflight; the real provider must also decode in its sandbox."""
    if not 16 <= len(data) <= MAX_IMAGE_BYTES:
        raise WorkerError("InvalidImageSize")
    png = data.startswith(b"\x89PNG\r\n\x1a\n")
    jpeg = data.startswith(b"\xff\xd8\xff") and data.endswith(b"\xff\xd9")
    if not png and not jpeg:
        raise WorkerError("UnsupportedImageFormat")
    if png:
        if len(data) < 33 or data[12:16] != b"IHDR":
            raise WorkerError("InvalidImage")
        width, height = struct.unpack_from(">II", data, 16)
        if not (1 <= width <= 8192 and 1 <= height <= 8192 and width * height <= 32_000_000):
            raise WorkerError("InvalidImageDimensions")


def validate_glb(data: bytes) -> dict[str, Any]:
    """Reject truncated, external-resource, or malformed GLB 2.0 containers."""
    if not 28 <= len(data) <= MAX_RESULT_BYTES:
        raise WorkerError("InvalidGlbSize")
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise WorkerError("InvalidGlbHeader")
    offset, chunks = 12, []
    while offset < len(data):
        if offset + 8 > len(data):
            raise WorkerError("InvalidGlbChunk")
        size, kind = struct.unpack_from("<I4s", data, offset)
        offset += 8
        if size % 4 or offset + size > len(data):
            raise WorkerError("InvalidGlbChunk")
        chunks.append((kind, data[offset : offset + size]))
        offset += size
    if not chunks or chunks[0][0] != b"JSON":
        raise WorkerError("InvalidGlbJson")
    try:
        document = json.loads(chunks[0][1])
    except (ValueError, UnicodeDecodeError) as exc:
        raise WorkerError("InvalidGlbJson") from exc
    if not isinstance(document, dict) or document.get("asset", {}).get("version") != "2.0":
        raise WorkerError("InvalidGlbJson")
    if any("uri" in item for key in ("buffers", "images") for item in document.get(key, [])):
        raise WorkerError("ExternalGlbResource")
    if not document.get("meshes") or not document.get("scenes"):
        raise WorkerError("EmptyGlb")
    buffers = document.get("buffers", [])
    binary = next((value for kind, value in chunks if kind == b"BIN\0"), b"")
    if len(buffers) != 1 or not isinstance(buffers[0].get("byteLength"), int):
        raise WorkerError("InvalidGlbBuffer")
    if not 0 <= len(binary) - buffers[0]["byteLength"] <= 3:
        raise WorkerError("InvalidGlbBuffer")
    for view in document.get("bufferViews", []):
        begin, size = view.get("byteOffset", 0), view.get("byteLength", -1)
        if view.get("buffer") != 0 or not isinstance(begin, int) or not isinstance(size, int):
            raise WorkerError("InvalidGlbBufferView")
        if begin < 0 or size < 0 or begin + size > buffers[0]["byteLength"]:
            raise WorkerError("InvalidGlbBufferView")
    return document


def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def preview_png(color: tuple[int, int, int], width: int = 256) -> bytes:
    """Orthographic flat-shaded box preview matching the fake GLB geometry."""
    pixels = bytearray(bytes((17, 22, 38)) * width * width)

    def polygon(points: list[tuple[float, float]], shade: float) -> None:
        mapped = [(int(x * width), int(y * width)) for x, y in points]
        tint = bytes(min(255, int(c * shade)) for c in color)
        for y in range(max(0, min(p[1] for p in mapped)), min(width, max(p[1] for p in mapped) + 1)):
            crossings = []
            for a, b in zip(mapped, mapped[1:] + mapped[:1]):
                if min(a[1], b[1]) <= y < max(a[1], b[1]):
                    crossings.append(a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
            crossings.sort()
            for left, right in zip(crossings[::2], crossings[1::2]):
                for x in range(max(0, math.ceil(left)), min(width, math.ceil(right))):
                    offset = 3 * (y * width + x)
                    pixels[offset : offset + 3] = tint

    polygon([(0.5, 0.2), (0.8, 0.36), (0.5, 0.53), (0.2, 0.36)], 1.15)
    polygon([(0.2, 0.36), (0.5, 0.53), (0.5, 0.85), (0.2, 0.68)], 0.8)
    polygon([(0.5, 0.53), (0.8, 0.36), (0.8, 0.68), (0.5, 0.85)], 0.55)
    rows = b"".join(b"\0" + pixels[y * width * 3 : (y + 1) * width * 3] for y in range(width))
    return b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, width, 8, 2, 0, 0, 0)) + _chunk(b"IDAT", zlib.compress(rows)) + _chunk(b"IEND", b"")


def cube_glb(color: tuple[int, int, int]) -> bytes:
    faces = [
        ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
        ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
        ((1, 0, 0), [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
        ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
        ((0, 1, 0), [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
        ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
    ]
    vertices = [axis * 0.5 for _, face in faces for vertex in face for axis in vertex]
    normals = [axis for normal, _ in faces for _ in range(4) for axis in normal]
    indices = [face * 4 + index for face in range(6) for index in (0, 1, 2, 0, 2, 3)]
    positions = struct.pack("<72f", *vertices)
    normal_data = struct.pack("<72f", *normals)
    binary = positions + normal_data + struct.pack("<36H", *indices)
    document = {
        "asset": {"version": "2.0", "generator": "Hedrion deterministic fake - not AI"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]}],
        "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [c / 255 for c in color] + [1], "metallicFactor": 0.1, "roughnessFactor": 0.6}}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 288, "target": 34962}, {"buffer": 0, "byteOffset": 288, "byteLength": 288, "target": 34962}, {"buffer": 0, "byteOffset": 576, "byteLength": 72, "target": 34963}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 24, "type": "VEC3", "min": [-0.5] * 3, "max": [0.5] * 3}, {"bufferView": 1, "componentType": 5126, "count": 24, "type": "VEC3"}, {"bufferView": 2, "componentType": 5123, "count": 36, "type": "SCALAR"}],
    }
    description = json.dumps(document, separators=(",", ":")).encode("utf-8")
    description += b" " * (-len(description) % 4)
    return struct.pack("<4sII", b"glTF", 2, 28 + len(description) + len(binary)) + struct.pack("<I4s", len(description), b"JSON") + description + struct.pack("<I4s", len(binary), b"BIN\0") + binary


class FakeGenerationProvider:
    name = "fake"

    def generate(self, request: GenerationInput) -> GenerationOutput:
        started = time.monotonic()
        seed = hashlib.sha256((request.source_image or b"") + (request.source_prompt or "").encode()).digest()
        color = tuple(75 + channel % 150 for channel in seed[:3])
        model, preview = cube_glb(color), preview_png(color)
        validate_glb(model)
        return GenerationOutput(request.job_id, self.name, model, preview,
            {"triangleCount": 12, "vertexCount": 24, "materialCount": 1, "demo": True, "sha256": hashlib.sha256(model).hexdigest()},
            {"inference_ms": round((time.monotonic() - started) * 1000), "output_size_bytes": len(model), "preview_size_bytes": len(preview), "gpu_type": "none"})

from __future__ import annotations

import base64
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from hedrion_worker.modal_config import ModalConfig
from hedrion_worker.pixal3d import Pixal3DCliProvider
from hedrion_worker.provider import GenerationInput, WorkerError, cube_glb, preview_png, validate_glb


@unittest.skipUnless(importlib.util.find_spec("PIL"), "Install requirements-real.txt to run CPU image/CLI contract tests")
class Pixal3DContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hedrion-cli-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.request = GenerationInput("job_123", "owner_123", "image_to_3d", preview_png((120, 140, 180), 32))

    def stub(self, behavior: str = "success"):
        model = base64.b64encode(cube_glb((120, 140, 180))).decode()
        body = {
            "success": f"output.write_bytes(base64.b64decode({model!r}))",
            "failure": "raise SystemExit(17)",
            "missing": "pass",
            "invalid": "output.write_bytes(b'invalid geometry container content')",
        }[behavior]
        script = f'''import argparse,base64,json,os
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument("--image",required=True)
p.add_argument("--output",required=True)
p.add_argument("--resolution",required=True)
p.add_argument("--low_vram",action="store_true")
a=p.parse_args()
source,output=Path(a.image),Path(a.output)
assert source.is_absolute() and output.is_absolute()
assert source.parent==output.parent
assert source.read_bytes().startswith(b"\\x89PNG")
assert "WORKER_SHARED_SECRET" not in os.environ
assert a.resolution=="1024" and a.low_vram
Path("invocation.json").write_text(json.dumps(vars(a)))
{body}
'''
        (self.root / "inference.py").write_text(script, encoding="utf-8")
        return Pixal3DCliProvider(self.root, Path(sys.executable))

    def test_real_adapter_invokes_only_verified_flags_and_validates_output(self):
        provider = self.stub()
        with patch.dict("os.environ", {"WORKER_SHARED_SECRET": "must-not-reach-inference"}):
            output = provider.generate(self.request)
        self.assertEqual(output.job_id, "job_123")
        self.assertEqual(output.provider, "pixal3d")
        self.assertFalse(output.metadata["demo"])
        self.assertEqual(output.metadata["triangleCount"], 12)
        self.assertEqual(output.metadata["previewKind"], "reference_image_fallback")
        self.assertFalse(output.metadata["previewIsGeneratedModel"])
        self.assertIsNone(output.metrics["peak_vram_mb"])
        self.assertIsNone(output.metrics["cost"])
        validate_glb(output.model)
        invocation = json.loads((self.root / "invocation.json").read_text())
        self.assertEqual(set(invocation), {"image", "output", "resolution", "low_vram"})
        self.assertFalse(Path(invocation["image"]).exists(), "Temporary inputs must be removed")
        from PIL import Image
        with Image.open(io.BytesIO(output.preview)) as image:
            image.load()
            self.assertGreaterEqual(image.width, 360)
            self.assertGreater(image.height, 48)
            self.assertEqual(image.format, "PNG")

    def test_text_path_rejected_without_inference_or_mock_downgrade(self):
        provider = self.stub()
        with patch("hedrion_worker.pixal3d.subprocess.run") as run:
            with self.assertRaises(WorkerError) as failure:
                provider.generate(GenerationInput("job", "owner", "text_to_3d", source_prompt="a chest"))
            self.assertEqual(failure.exception.code, "UnsupportedInput")
            run.assert_not_called()

    def test_failure_missing_result_and_invalid_glb_are_not_success(self):
        for behavior, code in (("failure", "InferenceFailed"), ("missing", "WorkerOutputMissing"), ("invalid", "InvalidGlbHeader")):
            with self.subTest(behavior=behavior):
                provider = self.stub(behavior)
                with self.assertRaises(WorkerError) as failure:
                    provider.generate(self.request)
                self.assertEqual(failure.exception.code, code)

    def test_timeout_uses_argument_array_and_sanitized_error(self):
        provider = self.stub()
        with patch("hedrion_worker.pixal3d.subprocess.run", side_effect=subprocess.TimeoutExpired(["private-root"], 1)) as run:
            with self.assertRaises(WorkerError) as failure:
                provider.generate(self.request)
            self.assertEqual(failure.exception.code, "InferenceTimeout")
            self.assertIsInstance(run.call_args.args[0], list)
            self.assertFalse(run.call_args.kwargs["shell"])
            self.assertEqual(run.call_args.kwargs["timeout"], 900)
            self.assertNotIn("private-root", str(failure.exception))

    def test_image_fully_decoded_before_launch(self):
        provider = self.stub()
        invalid_png = self.request.source_image[:33] + b"broken payload data"
        with patch("hedrion_worker.pixal3d.subprocess.run") as run:
            with self.assertRaises(WorkerError):
                provider.generate(GenerationInput("job", "owner", "image_to_3d", invalid_png))
            run.assert_not_called()

    def test_large_result_rejected_before_reading_or_returning_success(self):
        provider = self.stub()
        with patch("hedrion_worker.pixal3d.MAX_RESULT_BYTES", 30):
            with self.assertRaises(WorkerError) as failure:
                provider.generate(self.request)
            self.assertEqual(failure.exception.code, "InvalidGlbSize")

    def test_provider_configuration_never_silently_falls_back(self):
        with self.assertRaises(ValueError):
            Pixal3DCliProvider.from_environment({})
        self.stub()
        with self.assertRaises(ValueError):
            Pixal3DCliProvider.from_environment({"PIXAL3D_ROOT": str(self.root), "PIXAL3D_RESOLUTION": "512"})
        with self.assertRaises(ValueError):
            Pixal3DCliProvider(self.root, Path("relative-python"))
        with self.assertRaises(ValueError):
            Pixal3DCliProvider(self.root, timeout_seconds=1201)
        with self.assertRaises(ValueError):
            Pixal3DCliProvider.from_environment({"PIXAL3D_ROOT": str(self.root), "PIXAL3D_LOW_VRAM": "maybe"})


class ModalConfigurationTests(unittest.TestCase):
    def environment(self):
        return {"PIXAL3D_IMAGE": "registry.example.test/verified/pixal3d@sha256:" + "a" * 64,
                "MODAL_GPU": "L4", "MODAL_PIXAL3D_ROOT": "/opt/Pixal3D"}

    def test_digest_pin_gpu_and_linux_root_are_required(self):
        for missing in ("PIXAL3D_IMAGE", "MODAL_GPU", "MODAL_PIXAL3D_ROOT"):
            values = self.environment()
            values.pop(missing)
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                ModalConfig.from_environment(values)
        for key, value in (("PIXAL3D_IMAGE", "image:latest"), ("MODAL_GPU", "unverified"), ("MODAL_PIXAL3D_ROOT", "relative/path")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                ModalConfig.from_environment({**self.environment(), key: value})

    def test_configuration_does_not_import_sdk_or_trigger_deployment(self):
        config = ModalConfig.from_environment(self.environment())
        self.assertEqual(config.gpu, "L4")
        self.assertEqual(config.secret_name, "hedrion-worker")
        self.assertEqual(config.pixal_root, "/opt/Pixal3D")


if __name__ == "__main__":
    unittest.main()

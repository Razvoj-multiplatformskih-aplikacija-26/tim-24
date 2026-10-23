from __future__ import annotations

import base64
import concurrent.futures
import hashlib
import http.client
import json
import struct
import threading
import time
import unittest
from unittest.mock import patch

from hedrion_worker.provider import (
    FakeGenerationProvider,
    GenerationInput,
    WorkerError,
    cube_glb,
    preview_png,
    validate_glb,
    validate_image_header,
)
from hedrion_worker.server import RequestAuthenticator, WorkerApplication, make_server, signature

SECRET = "test-worker-secret-containing-32-characters"


def input_payload(job: str = "job_1") -> dict:
    return {"jobId": job, "ownerId": "creator_1", "inputType": "image_to_3d", "sourceImageBase64": base64.b64encode(preview_png((100, 120, 200), 32)).decode()}


class ProviderTests(unittest.TestCase):
    def test_fake_is_deterministic_and_produces_real_mesh_and_preview(self):
        provider = FakeGenerationProvider()
        request = GenerationInput.from_json(input_payload())
        first, second = provider.generate(request), provider.generate(request)
        self.assertEqual(first.model, second.model)
        self.assertEqual(first.preview, second.preview)
        document = validate_glb(first.model)
        self.assertEqual(document["accessors"][2]["count"] // 3, first.metadata["triangleCount"])
        self.assertEqual(first.metadata["triangleCount"], 12)
        self.assertEqual(first.metadata["sha256"], hashlib.sha256(first.model).hexdigest())
        self.assertTrue(first.preview.startswith(b"\x89PNG"))
        self.assertEqual(first.metrics["output_size_bytes"], len(first.model))
        self.assertEqual(first.provider, "fake")
        self.assertTrue(first.metadata["demo"])

    def test_mock_text_is_explicit_and_distinct(self):
        provider = FakeGenerationProvider()
        first = provider.generate(GenerationInput.from_json({"jobId": "one", "ownerId": "user", "inputType": "text_to_3d", "sourcePrompt": "a chest"}))
        second = provider.generate(GenerationInput.from_json({"jobId": "two", "ownerId": "user", "inputType": "text_to_3d", "sourcePrompt": "a rock"}))
        self.assertNotEqual(first.model, second.model)
        self.assertEqual(first.provider, "fake")

    def test_inputs_are_validated(self):
        for payload in (None, {}, input_payload("../path"), {**input_payload(), "sourceImageBase64": "not base64"}, {**input_payload(), "inputType": "unknown"}, {"jobId": "x", "ownerId": "y", "inputType": "image_to_3d"}):
            with self.subTest(payload=str(payload)[:60]), self.assertRaises(WorkerError):
                GenerationInput.from_json(payload)

    def test_image_magic_and_dimensions(self):
        with self.assertRaises(WorkerError):
            validate_image_header(b"arbitrary untrusted data")
        image = bytearray(preview_png((1, 2, 3), 8))
        struct.pack_into(">I", image, 16, 30_000)
        with self.assertRaises(WorkerError):
            validate_image_header(bytes(image))

    def test_glb_truncation_and_header_rejected(self):
        model = cube_glb((120, 140, 180))
        for invalid in (b"", model[:-1], b"bad!" + model[4:], model[:4] + struct.pack("<I", 1) + model[8:]):
            with self.subTest(size=len(invalid)), self.assertRaises(WorkerError):
                validate_glb(invalid)

    def test_mesh_winding_matches_normals(self):
        model = cube_glb((1, 2, 3))
        document = validate_glb(model)
        json_size = struct.unpack_from("<I", model, 12)[0]
        binary_start = 28 + json_size
        positions = struct.unpack_from("<72f", model, binary_start)
        normals = struct.unpack_from("<72f", model, binary_start + 288)
        indices = struct.unpack_from("<36H", model, binary_start + 576)
        for i in range(0, len(indices), 3):
            vertices = [positions[j * 3 : j * 3 + 3] for j in indices[i : i + 3]]
            a = [vertices[1][k] - vertices[0][k] for k in range(3)]
            b = [vertices[2][k] - vertices[0][k] for k in range(3)]
            cross = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
            normal = normals[indices[i] * 3 : indices[i] * 3 + 3]
            self.assertGreater(sum(cross[k] * normal[k] for k in range(3)), 0)
        self.assertEqual(document["asset"]["version"], "2.0")


class SecurityTests(unittest.TestCase):
    def headers(self, body: bytes, timestamp: str = "1000", nonce: str = "nonce_for_test_0001") -> dict:
        return {"Authorization": "Bearer " + SECRET, "X-Hedrion-Timestamp": timestamp, "X-Hedrion-Nonce": nonce, "X-Hedrion-Signature": signature(SECRET, timestamp, nonce, body)}

    def test_authentic_request_then_replay_rejected(self):
        authenticator = RequestAuthenticator(SECRET)
        headers = self.headers(b"{}")
        authenticator.verify(headers, b"{}", now=1000)
        with self.assertRaises(WorkerError) as failure:
            authenticator.verify(headers, b"{}", now=1001)
        self.assertEqual(failure.exception.code, "ReplayedRequest")

    def test_tampering_staleness_and_bad_token_rejected(self):
        authenticator = RequestAuthenticator(SECRET)
        for headers, body, now in ((self.headers(b"{}"), b"changed", 1000), (self.headers(b"{}"), b"{}", 1600), ({**self.headers(b"{}"), "Authorization": "Bearer wrong"}, b"{}", 1000)):
            with self.subTest(now=now, body=body), self.assertRaises(WorkerError):
                authenticator.verify(headers, body, now=now)

    def test_secret_must_be_configured(self):
        with self.assertRaises(ValueError):
            RequestAuthenticator("")


class ApplicationTests(unittest.TestCase):
    def test_completed_job_replay_is_idempotent(self):
        provider = FakeGenerationProvider()
        application = WorkerApplication(provider, SECRET)
        with patch.object(provider, "generate", wraps=provider.generate) as generate:
            first = application.generate(input_payload())
            self.assertEqual(first, application.generate(input_payload()))
            self.assertEqual(generate.call_count, 1)
        with self.assertRaises(WorkerError) as failure:
            application.generate({**input_payload(), "sourcePrompt": "changed"})
        self.assertEqual(failure.exception.code, "JobPayloadConflict")

    def test_busy_and_duplicate_active_job_do_not_start_another_inference(self):
        provider = FakeGenerationProvider()
        application = WorkerApplication(provider, SECRET, max_concurrency=1)
        entered, release = threading.Event(), threading.Event()
        real_generate = provider.generate

        def blocked(request):
            entered.set()
            release.wait(timeout=5)
            return real_generate(request)

        with patch.object(provider, "generate", side_effect=blocked):
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(application.generate, input_payload())
                self.assertTrue(entered.wait(timeout=3))
                try:
                    with self.assertRaises(WorkerError) as duplicate:
                        application.generate(input_payload())
                    self.assertEqual(duplicate.exception.code, "JobAlreadyRunning")
                    with self.assertRaises(WorkerError) as busy:
                        application.generate(input_payload("different"))
                    self.assertEqual(busy.exception.code, "WorkerBusy")
                finally:
                    release.set()
                self.assertEqual(future.result(timeout=5)["jobId"], "job_1")

    def test_failure_releases_capacity(self):
        provider = FakeGenerationProvider()
        application = WorkerApplication(provider, SECRET, max_concurrency=1)
        with patch.object(provider, "generate", side_effect=WorkerError("FakeFailure")):
            with self.assertRaises(WorkerError):
                application.generate(input_payload())
        self.assertEqual(application.generate(input_payload())["jobId"], "job_1")


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server("127.0.0.1", 0, WorkerApplication(FakeGenerationProvider(), SECRET))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def request(self, method: str, path: str, payload=None, authenticated=False):
        body = json.dumps(payload).encode() if payload is not None else b""
        headers = {"Content-Type": "application/json"}
        if authenticated:
            stamp, nonce = str(int(time.time())), "http_nonce_" + str(time.time_ns())
            headers.update({"Authorization": "Bearer " + SECRET, "X-Hedrion-Timestamp": stamp, "X-Hedrion-Nonce": nonce, "X-Hedrion-Signature": signature(SECRET, stamp, nonce, body)})
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_health_without_auth(self):
        self.assertEqual(self.request("GET", "/health"), (200, {"status": "ok", "provider": "fake"}))

    def test_private_generation_requires_auth(self):
        status, body = self.request("POST", "/internal/v1/generate", input_payload())
        self.assertEqual(status, 401)
        self.assertEqual(body["code"], "Unauthorized")

    def test_signed_end_to_end_generation(self):
        status, result = self.request("POST", "/internal/v1/generate", input_payload("http_job"), authenticated=True)
        self.assertEqual(status, 200)
        validate_glb(base64.b64decode(result["modelBase64"]))
        self.assertEqual(result["jobId"], "http_job")
        self.assertEqual(result["provider"], "fake")


if __name__ == "__main__":
    unittest.main()

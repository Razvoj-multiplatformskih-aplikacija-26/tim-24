"""Authenticated, bounded, internal HTTP bridge; never expose it to clients."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import threading
import time
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .provider import (
    FakeGenerationProvider,
    GenerationInput,
    GenerationProvider,
    WorkerError,
    validate_glb,
    validate_image_header,
)

MAX_BODY_BYTES = 13_400_000
SIGNATURE_WINDOW_SECONDS = 300


def signature(secret: str, timestamp: str, nonce: str, body: bytes) -> str:
    message = timestamp.encode() + b"." + nonce.encode() + b"." + body
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


class RequestAuthenticator:
    def __init__(self, secret: str):
        if len(secret) < 32:
            raise ValueError("WORKER_SHARED_SECRET must contain at least 32 characters")
        self.secret = secret
        self._nonces: dict[str, float] = {}
        self._lock = threading.Lock()

    def verify(self, headers: Any, body: bytes, now: float | None = None) -> None:
        now = time.time() if now is None else now
        bearer = headers.get("Authorization", "")
        stamp = headers.get("X-Hedrion-Timestamp", "")
        nonce = headers.get("X-Hedrion-Nonce", "")
        digest = headers.get("X-Hedrion-Signature", "")
        if not hmac.compare_digest(bearer, "Bearer " + self.secret):
            raise WorkerError("Unauthorized", 401)
        if not re.fullmatch(r"[0-9]{1,12}", stamp) or abs(now - int(stamp)) > SIGNATURE_WINDOW_SECONDS:
            raise WorkerError("StaleSignature", 401)
        if not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", nonce):
            raise WorkerError("InvalidNonce", 401)
        if not hmac.compare_digest(digest, signature(self.secret, stamp, nonce, body)):
            raise WorkerError("InvalidSignature", 401)
        with self._lock:
            self._nonces = {key: expires for key, expires in self._nonces.items() if expires > now}
            if nonce in self._nonces:
                raise WorkerError("ReplayedRequest", 409)
            if len(self._nonces) >= 10_000:
                raise WorkerError("RequestLimitExceeded", 429)
            self._nonces[nonce] = now + SIGNATURE_WINDOW_SECONDS * 2


class WorkerApplication:
    def __init__(self, provider: GenerationProvider, secret: str, max_concurrency: int = 2):
        if not 1 <= max_concurrency <= 2:
            raise ValueError("Worker concurrency must be 1 or 2")
        self.provider = provider
        self.authenticator = RequestAuthenticator(secret)
        self._permits = threading.BoundedSemaphore(max_concurrency)
        self._lock = threading.Lock()
        self._active: set[str] = set()
        self._results: OrderedDict[str, tuple[str, dict[str, Any]]] = OrderedDict()
        self._cached_bytes = 0

    def generate(self, data: Any) -> dict[str, Any]:
        request = GenerationInput.from_json(data)
        fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        with self._lock:
            previous = self._results.get(request.job_id)
            if previous is not None:
                if not hmac.compare_digest(previous[0], fingerprint):
                    raise WorkerError("JobPayloadConflict", 409)
                return previous[1]
            if request.job_id in self._active:
                raise WorkerError("JobAlreadyRunning", 409)
            if not self._permits.acquire(blocking=False):
                raise WorkerError("WorkerBusy", 503)
            self._active.add(request.job_id)
        try:
            output = self.provider.generate(request)
            if output.job_id != request.job_id:
                raise WorkerError("ProviderJobMismatch", 502)
            validate_glb(output.model)
            validate_image_header(output.preview)
            result = output.to_json()
            result_bytes = len(result["modelBase64"]) + len(result["previewBase64"])
            with self._lock:
                if result_bytes <= 32_000_000:
                    self._results[request.job_id] = (fingerprint, result)
                    self._cached_bytes += result_bytes
                    while len(self._results) > 128 or self._cached_bytes > 32_000_000:
                        _, (_, evicted) = self._results.popitem(last=False)
                        self._cached_bytes -= len(evicted["modelBase64"]) + len(evicted["previewBase64"])
            return result
        finally:
            with self._lock:
                self._active.discard(request.job_id)
            self._permits.release()


def make_server(host: str, port: int, application: WorkerApplication) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        server_version = "HedrionWorker/1"

        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(30)

        def log_message(self, format: str, *args: Any) -> None:
            # URLs, input bodies, bearer credentials and provider output are never logged.
            pass

        def respond(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path == "/health":
                self.respond(200, {"status": "ok", "provider": application.provider.name})
            else:
                self.respond(404, {"code": "NotFound"})

        def do_POST(self) -> None:
            if self.path != "/internal/v1/generate":
                self.respond(404, {"code": "NotFound"})
                return
            try:
                raw_length = self.headers.get("Content-Length", "")
                if not re.fullmatch(r"[0-9]{1,9}", raw_length):
                    raise WorkerError("ContentLengthRequired", 411)
                length = int(raw_length)
                if not 1 <= length <= MAX_BODY_BYTES:
                    raise WorkerError("RequestTooLarge", 413)
                if self.headers.get_content_type() != "application/json":
                    raise WorkerError("UnsupportedMediaType", 415)
                body = self.rfile.read(length)
                if len(body) != length:
                    raise WorkerError("IncompleteRequest", 400)
                application.authenticator.verify(self.headers, body)
                try:
                    data = json.loads(body)
                except (ValueError, UnicodeDecodeError) as exc:
                    raise WorkerError("InvalidJson", 400) from exc
                self.respond(200, application.generate(data))
            except WorkerError as exc:
                self.respond(exc.status, {"code": exc.code})
            except (ConnectionError, TimeoutError):
                self.close_connection = True
            except Exception:
                # Do not expose model paths, stack traces, provider credentials or inputs.
                self.respond(500, {"code": "WorkerFailure"})

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


def main() -> None:
    parser = argparse.ArgumentParser(description="Hedrion internal generation worker")
    parser.add_argument("--host", default=os.getenv("WORKER_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.getenv("WORKER_PORT", "8091")))
    args = parser.parse_args()
    secret = os.getenv("WORKER_SHARED_SECRET", "")
    provider_name = os.getenv("GENERATION_PROVIDER", "fake")
    try:
        if provider_name == "fake":
            provider = FakeGenerationProvider()
        elif provider_name == "pixal3d":
            if os.getenv("ENABLE_EXPERIMENTAL_PROVIDER", "false").lower() != "true":
                raise ValueError(
                    "No production AI model has been selected. The retained Pixal3D adapter is experimental and disabled."
                )
            from .pixal3d import Pixal3DCliProvider

            provider = Pixal3DCliProvider.from_environment()
        else:
            raise ValueError("No registered provider selected. Use fake for the local demo.")
        concurrency = int(os.getenv("WORKER_MAX_CONCURRENCY", "1" if provider_name == "pixal3d" else "2"))
        application = WorkerApplication(provider, secret, max_concurrency=concurrency)
    except ValueError as exc:
        parser.error(str(exc))
    server = make_server(args.host, args.port, application)
    print(f"Hedrion worker: provider={application.provider.name}; address={args.host}:{server.server_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

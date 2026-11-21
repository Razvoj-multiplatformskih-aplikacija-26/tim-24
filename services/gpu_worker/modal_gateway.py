"""Private asynchronous Modal bridge. Only the Dart server calls this service.

Deployment: python -m modal deploy modal_gateway.py
Requires Modal Secret ``hedrion-worker`` containing WORKER_SHARED_SECRET.
The gateway never allocates a GPU. Model-specific apps own their environments.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import time
from pathlib import Path
from typing import Any, Callable, Protocol

from hedrion_worker.provider import (
    GenerationInput,
    WorkerError,
    validate_glb,
    validate_image_header,
)
from hedrion_worker.server import MAX_BODY_BYTES, RequestAuthenticator

MODEL_APPS = {
    "spar3d": "hedrion-spar3d",
    "hunyuan3d_21": "hedrion-hunyuan3d",
    "trellis2": "hedrion-trellis2",
}
_IDENTIFIER = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


class JobStore(Protocol):
    def get(self, key: Any, default: Any = None) -> Any: ...

    def put(self, key: Any, value: Any, *, skip_if_exists: bool = False) -> bool: ...


def validate_payload(data: Any) -> dict[str, Any]:
    request = GenerationInput.from_json(data)
    provider = data.get("modelProvider", "spar3d")
    if not isinstance(provider, str) or provider not in MODEL_APPS:
        raise WorkerError("UnsupportedModel", 422)
    seed = data.get("seed", 42)
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed < 2**32:
        raise WorkerError("InvalidSeed", 422)
    # Normalize the exact fields delivered to the model. Extra client fields
    # cannot alter worker behavior outside the recorded idempotency fingerprint.
    return {
        "jobId": request.job_id,
        "ownerId": request.owner_id,
        "inputType": request.input_type,
        "sourcePrompt": request.source_prompt,
        "sourceImageBase64": data.get("sourceImageBase64"),
        "modelProvider": provider,
        "seed": seed,
    }


class GatewayController:
    """Durable admission with an atomic reservation before any billed dispatch."""

    def __init__(self, store: JobStore, dispatch: Callable[[dict[str, Any]], str],
                 poll: Callable[[str], Any]):
        self.store, self.dispatch, self.poll = store, dispatch, poll

    @staticmethod
    def _check_owner(record: dict[str, Any], owner: str) -> None:
        if not hmac.compare_digest(record["ownerId"], owner):
            raise WorkerError("JobNotFound", 404)

    def submit(self, data: Any) -> dict[str, Any]:
        payload = validate_payload(data)
        fingerprint = hashlib.sha256(json.dumps(
            payload, sort_keys=True, separators=(",", ":"),
        ).encode()).hexdigest()
        key = "job:" + payload["jobId"]
        reservation = {
            "ownerId": payload["ownerId"], "fingerprint": fingerprint,
            "state": "dispatching", "createdAt": time.time(),
        }
        won = self.store.put(key, reservation, skip_if_exists=True)
        if not won:
            previous = self.store.get(key)
            if previous is None:
                # Lost/expired reservations must not create another paid call.
                raise WorkerError("DispatchUnknown", 503)
            self._check_owner(previous, payload["ownerId"])
            if not hmac.compare_digest(previous["fingerprint"], fingerprint):
                raise WorkerError("JobPayloadConflict", 409)
            if previous["state"] == "dispatchFailed":
                raise WorkerError("DispatchFailed", 422)
            return {"jobId": payload["jobId"], "status": "running"}
        try:
            call_id = self.dispatch(payload)
            self.store.put(key, {**reservation, "state": "running", "callId": call_id})
        except Exception as exc:
            # Never release the reservation: the remote submit might already
            # have succeeded even if its acknowledgement was lost.
            self.store.put(key, {**reservation, "state": "dispatchFailed"})
            raise WorkerError("DispatchFailed", 502) from exc
        return {"jobId": payload["jobId"], "status": "running"}

    def result(self, data: Any) -> tuple[int, dict[str, Any]]:
        if not isinstance(data, dict) or any(
            not isinstance(data.get(field), str) or not _IDENTIFIER.fullmatch(data[field])
            for field in ("jobId", "ownerId")
        ):
            raise WorkerError("InvalidIdentifier", 422)
        record = self.store.get("job:" + data["jobId"])
        if record is None:
            raise WorkerError("JobNotFound", 404)
        self._check_owner(record, data["ownerId"])
        if record["state"] == "dispatchFailed":
            raise WorkerError("DispatchFailed", 422)
        if record["state"] == "dispatching":
            if time.time() - record["createdAt"] > 120:
                raise WorkerError("DispatchUnknown", 409)
            return 202, {"jobId": data["jobId"], "status": "running"}
        try:
            output = self.poll(record["callId"])
        except TimeoutError:
            return 202, {"jobId": data["jobId"], "status": "running"}
        except Exception as exc:
            raise WorkerError("GenerationFailed", 422) from exc
        if not isinstance(output, dict) or output.get("jobId") != data["jobId"]:
            raise WorkerError("ProviderJobMismatch", 502)
        return 200, output


def execute_pipeline(payload: dict[str, Any], invoke: Callable[[str, dict[str, Any]], dict[str, Any]]) -> dict[str, Any]:
    """Compose text → reference PNG → 3D without involving a client session."""
    payload = validate_payload(payload)
    started = time.monotonic()
    reference = None
    image_payload = dict(payload)
    if payload["inputType"] == "text_to_3d":
        reference = invoke("hedrion-qwen-image", {
            "jobId": payload["jobId"], "ownerId": payload["ownerId"],
            "sourcePrompt": payload["sourcePrompt"], "seed": payload["seed"],
        })
        if reference.get("jobId") != payload["jobId"]:
            raise WorkerError("ProviderJobMismatch", 502)
        try:
            image_bytes = base64.b64decode(reference["imageBase64"], validate=True)
            validate_image_header(image_bytes)
        except (KeyError, ValueError) as exc:
            raise WorkerError("InvalidReferenceImage", 502) from exc
        image_payload.update(inputType="image_to_3d", sourceImageBase64=reference["imageBase64"])
    output = invoke(MODEL_APPS[payload["modelProvider"]], image_payload)
    if output.get("jobId") != payload["jobId"]:
        raise WorkerError("ProviderJobMismatch", 502)
    if output.get("provider") != payload["modelProvider"]:
        raise WorkerError("ProviderModelMismatch", 502)
    try:
        validate_glb(base64.b64decode(output["modelBase64"], validate=True))
        validate_image_header(base64.b64decode(output["previewBase64"], validate=True))
    except (KeyError, ValueError) as exc:
        raise WorkerError("InvalidProviderOutput", 502) from exc
    output = {**output, "metrics": {**output.get("metrics", {}),
                                   "pipeline_elapsed_ms": round((time.monotonic() - started) * 1000)}}
    if reference is not None:
        output["referenceImageBase64"] = reference["imageBase64"]
        output["referenceImageMime"] = "image/png"
        output["referenceImageMetrics"] = reference.get("metrics", {})
        output["metadata"] = {**output.get("metadata", {}),
                              "referenceImageProvider": reference.get("provider"),
                              "referenceImageMetadata": reference.get("metadata", {})}
    return output


def _create_modal_app():
    # The pure controller/pipeline can be tested without the optional Modal SDK.
    import modal

    image = (modal.Image.debian_slim(python_version="3.12")
             .pip_install("fastapi==0.162.7")
             .env({"PYTHONPATH": "/opt/hedrion"})
             .add_local_dir(Path(__file__).parent / "hedrion_worker", "/opt/hedrion/hedrion_worker",
                            ignore=["__pycache__", "*.pyc"]))
    app = modal.App("hedrion-modal-gateway", image=image,
                    tags={"project": "hedrion", "component": "gateway"})
    jobs = modal.Dict.from_name("hedrion-generation-calls", create_if_missing=True)
    nonces = modal.Dict.from_name("hedrion-worker-nonces", create_if_missing=True)

    return app, jobs, nonces


try:
    import modal
except ImportError:
    app = None
else:
    app, jobs, nonces = _create_modal_app()
    @app.function(timeout=2700, cpu=0.25, memory=512, min_containers=0,
                  max_containers=2, retries=0, scaledown_window=2)
    def orchestrate(payload: dict) -> dict:
        def invoke(app_name: str, data: dict) -> dict:
            return modal.Function.from_name(app_name, "generate").remote(data)

        return execute_pipeline(payload, invoke)

    @app.function(secrets=[modal.Secret.from_name("hedrion-worker")],
                  min_containers=0, max_containers=1, cpu=0.25, memory=768,
                  timeout=300, scaledown_window=2)
    @modal.concurrent(max_inputs=32)
    @modal.asgi_app()
    def gateway():
        from fastapi import FastAPI, Request
        from fastapi.responses import JSONResponse

        auth = RequestAuthenticator(os.environ["WORKER_SHARED_SECRET"])
        controller = GatewayController(
            jobs, lambda data: orchestrate.spawn(data).object_id,
            lambda call_id: modal.FunctionCall.from_id(call_id).get(timeout=0),
        )
        web = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

        @web.get("/health")
        def health():
            return {"status": "ok", "provider": "modal", "models": list(MODEL_APPS),
                    "referenceImageProvider": "qwen_image_21_turbo"}

        async def parse(request: Request) -> dict:
            if request.headers.get("content-type", "").split(";")[0] != "application/json":
                raise WorkerError("UnsupportedMediaType", 415)
            limit = MAX_BODY_BYTES if request.url.path.endswith("/generate") else 4096
            raw = bytearray()
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > limit:
                    raise WorkerError("RequestTooLarge", 413)
            auth.verify(request.headers, bytes(raw))
            # Modal containers can restart; reject replay across container lives.
            nonce = request.headers.get("x-hedrion-nonce")
            if not nonces.put(nonce, int(time.time()), skip_if_exists=True):
                raise WorkerError("ReplayedRequest", 409)
            try:
                data = json.loads(raw)
            except (ValueError, UnicodeDecodeError) as exc:
                raise WorkerError("InvalidJson", 400) from exc
            return data

        @web.post("/internal/v1/generate")
        async def submit(request: Request):
            try:
                data = await parse(request)
                # Sync Modal IO runs in a thread: result polls remain responsive.
                import asyncio
                value = await asyncio.to_thread(controller.submit, data)
                return JSONResponse(value, status_code=202, headers={"Cache-Control": "no-store"})
            except WorkerError as exc:
                return JSONResponse({"code": exc.code}, status_code=exc.status)
            except Exception:
                return JSONResponse({"code": "GatewayUnavailable"}, status_code=503)

        @web.post("/internal/v1/result")
        async def result(request: Request):
            try:
                data = await parse(request)
                import asyncio
                status, value = await asyncio.to_thread(controller.result, data)
                return JSONResponse(value, status_code=status, headers={"Cache-Control": "no-store"})
            except WorkerError as exc:
                return JSONResponse({"code": exc.code}, status_code=exc.status)
            except Exception:
                return JSONResponse({"code": "GatewayUnavailable"}, status_code=503)

        return web

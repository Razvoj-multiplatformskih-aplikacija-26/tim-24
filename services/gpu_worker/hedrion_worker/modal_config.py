"""Validated deployment inputs; imports no Modal SDK and performs no cloud actions."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Mapping


@dataclass(frozen=True)
class ModalConfig:
    image: str
    gpu: str
    pixal_root: str
    app_name: str
    secret_name: str
    python_executable: str | None = None

    @classmethod
    def from_environment(cls, env: Mapping[str, str] | None = None) -> ModalConfig:
        env = os.environ if env is None else env
        image = env.get("PIXAL3D_IMAGE", "")
        if not re.fullmatch(r"[A-Za-z0-9./_:-]+@sha256:[0-9a-f]{64}", image):
            raise ValueError("PIXAL3D_IMAGE must be your verified Linux/amd64 registry image pinned by sha256 digest")
        gpu = env.get("MODAL_GPU", "")
        if gpu not in ("L4", "L40S"):
            raise ValueError("Explicitly select MODAL_GPU=L4 or L40S after validating that image on this GPU")
        root = env.get("MODAL_PIXAL3D_ROOT", "")
        if not root or not PurePosixPath(root).is_absolute() or ".." in PurePosixPath(root).parts or "\\" in root:
            raise ValueError("MODAL_PIXAL3D_ROOT must be the absolute Linux checkout path in your verified image")
        python = env.get("MODAL_PIXAL3D_PYTHON")
        if python and (not PurePosixPath(python).is_absolute() or "\\" in python):
            raise ValueError("MODAL_PIXAL3D_PYTHON must be an absolute Linux executable path")
        app = env.get("MODAL_APP_NAME", "hedrion-gpu-worker")
        secret = env.get("MODAL_WORKER_SECRET_NAME", "hedrion-worker")
        if any(not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", name) for name in (app, secret)):
            raise ValueError("Invalid Modal app or secret name")
        return cls(image, gpu, root, app, secret, python)

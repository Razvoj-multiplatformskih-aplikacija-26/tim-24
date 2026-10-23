"""Unselected experimental deployment reference; not the active product setup.

No cloud or AI model has been selected for Hedrion. This retained reference
requires a real prebuilt, digest-pinned Pixal3D image. Nothing in this file builds
or claims to validate CUDA dependencies or model weights. Importing this file
defines resources; deployment is an explicit separate operator action.
"""

import os
import subprocess
import sys
from pathlib import Path

import modal

from hedrion_worker.modal_config import ModalConfig

config = ModalConfig.from_environment()
image = modal.Image.from_registry(config.image).add_local_dir(
    Path(__file__).parent / "hedrion_worker",
    "/opt/hedrion/hedrion_worker",
    ignore=["__pycache__", "*.pyc"],
)
app = modal.App(config.app_name)


@app.function(
    image=image,
    gpu=config.gpu,
    secrets=[modal.Secret.from_name(config.secret_name)],
    env={
        "GENERATION_PROVIDER": "pixal3d",
        "ENABLE_EXPERIMENTAL_PROVIDER": "true",
        "PIXAL3D_ROOT": config.pixal_root,
        "PIXAL3D_GPU": config.gpu,
        "PIXAL3D_LOW_VRAM": "true",
        "PIXAL3D_RESOLUTION": "1024",
        "PIXAL3D_TIMEOUT_SECONDS": "900",
        "WORKER_MAX_CONCURRENCY": "1",
        **({"PIXAL3D_PYTHON": config.python_executable} if config.python_executable else {}),
    },
    min_containers=0,
    max_containers=2,
    timeout=1200,
)
@modal.web_server(8091, startup_timeout=60)
def worker_server():
    # The same HMAC-authenticated bridge is used locally and in the container.
    # No shell: no untrusted command, path or argument is interpolated.
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "/opt/hedrion" + (
        os.pathsep + environment["PYTHONPATH"] if environment.get("PYTHONPATH") else ""
    )
    subprocess.Popen(
        [sys.executable, "-m", "hedrion_worker.server", "--host", "0.0.0.0", "--port", "8091"],
        cwd="/opt/hedrion",
        env=environment,
        stdin=subprocess.DEVNULL,
        shell=False,
    )

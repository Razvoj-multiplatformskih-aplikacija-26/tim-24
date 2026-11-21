"""CPU contracts for admission, ownership and text/reference/model composition."""

import base64
import concurrent.futures
import threading
import unittest

from hedrion_worker.provider import WorkerError, cube_glb, preview_png
from modal_gateway import GatewayController, execute_pipeline, validate_payload


def payload(**changes):
    return {
        "jobId": "test_job", "ownerId": "creator_a", "inputType": "image_to_3d",
        "sourceImageBase64": base64.b64encode(preview_png((10, 30, 60), 32)).decode(),
        "modelProvider": "trellis2", "seed": 42, **changes,
    }


class AtomicMemoryStore:
    def __init__(self):
        self.items = {}
        self.lock = threading.Lock()

    def get(self, key, default=None):
        with self.lock:
            return self.items.get(key, default)

    def put(self, key, value, *, skip_if_exists=False):
        with self.lock:
            if skip_if_exists and key in self.items:
                return False
            self.items[key] = value
            return True


def generated(data):
    return {
        "jobId": data["jobId"], "provider": data["modelProvider"],
        "modelBase64": base64.b64encode(cube_glb((70, 90, 110))).decode(),
        "previewBase64": base64.b64encode(preview_png((70, 90, 110), 32)).decode(),
        "metadata": {"demo": True}, "metrics": {"inference_ms": 12},
    }


class GatewayTests(unittest.TestCase):
    def make_controller(self, dispatch=None, poll=None):
        self.calls = []

        def submit(data):
            self.calls.append(data)
            return "call_test"

        return GatewayController(AtomicMemoryStore(), dispatch or submit,
                                 poll or (lambda _: generated(payload())))

    def test_concurrent_identical_admissions_dispatch_only_once(self):
        controller = self.make_controller()
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            results = list(pool.map(lambda _: controller.submit(payload()), range(24)))
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(all(result["jobId"] == "test_job" for result in results))
        self.assertEqual(controller.result({"jobId": "test_job", "ownerId": "creator_a"})[0], 200)

    def test_different_payload_cannot_reuse_job_id(self):
        controller = self.make_controller()
        controller.submit(payload())
        with self.assertRaises(WorkerError) as error:
            controller.submit(payload(seed=43))
        self.assertEqual(error.exception.code, "JobPayloadConflict")
        self.assertEqual(len(self.calls), 1)

    def test_other_owner_cannot_submit_or_read_existing_job(self):
        controller = self.make_controller()
        controller.submit(payload())
        for action in (lambda: controller.submit(payload(ownerId="creator_b")),
                       lambda: controller.result({"jobId": "test_job", "ownerId": "creator_b"})):
            with self.assertRaises(WorkerError) as error:
                action()
            self.assertEqual(error.exception.status, 404)

    def test_uncertain_dispatch_is_never_automatically_repeated(self):
        calls = []

        def uncertain(data):
            calls.append(data)
            raise ConnectionError("acknowledgement lost")

        controller = self.make_controller(dispatch=uncertain)
        for _ in range(2):
            with self.assertRaises(WorkerError):
                controller.submit(payload())
        self.assertEqual(len(calls), 1)

    def test_poll_pending_is_202_but_model_failure_is_terminal(self):
        def pending(_):
            raise TimeoutError()

        controller = self.make_controller(poll=pending)
        controller.submit(payload())
        self.assertEqual(controller.result({"jobId": "test_job", "ownerId": "creator_a"})[0], 202)

        def failed(_):
            raise RuntimeError("private provider exception")

        controller.poll = failed
        with self.assertRaises(WorkerError) as error:
            controller.result({"jobId": "test_job", "ownerId": "creator_a"})
        self.assertEqual((error.exception.status, error.exception.code), (422, "GenerationFailed"))

    def test_invalid_seed_and_model_rejected_before_dispatch(self):
        controller = self.make_controller()
        for changes in ({"seed": -1}, {"seed": True}, {"seed": 2**32},
                        {"modelProvider": "shell_command"}, {"modelProvider": []}):
            with self.subTest(changes=changes), self.assertRaises(WorkerError):
                controller.submit(payload(**changes))
        self.assertEqual(self.calls, [])

    def test_missing_or_invalid_result_identifier_is_rejected(self):
        controller = self.make_controller()
        for data in ({}, {"jobId": "../job", "ownerId": "creator_a"},
                     {"jobId": "missing", "ownerId": "creator_a"}):
            with self.subTest(data=data), self.assertRaises(WorkerError):
                controller.result(data)

    def test_image_route_calls_only_selected_model(self):
        calls = []

        def invoke(app_name, data):
            calls.append(app_name)
            return generated(data)

        output = execute_pipeline(payload(), invoke)
        self.assertEqual(calls, ["hedrion-trellis2"])
        self.assertNotIn("referenceImageBase64", output)
        self.assertIn("pipeline_elapsed_ms", output["metrics"])

    def test_text_route_preserves_generated_reference_and_metrics(self):
        calls = []
        image = payload()["sourceImageBase64"]

        def invoke(app_name, data):
            calls.append((app_name, data))
            if app_name == "hedrion-qwen-image":
                return {"jobId": data["jobId"], "provider": "qwen_image_21_turbo",
                        "imageBase64": image, "metrics": {"inference_ms": 20}}
            self.assertEqual(data["sourceImageBase64"], image)
            self.assertEqual(data["inputType"], "image_to_3d")
            return generated(data)

        output = execute_pipeline(payload(inputType="text_to_3d", sourceImageBase64=None,
                                          sourcePrompt="A brass owl"), invoke)
        self.assertEqual([name for name, _ in calls], ["hedrion-qwen-image", "hedrion-trellis2"])
        self.assertEqual(output["referenceImageBase64"], image)
        self.assertEqual(output["referenceImageMetrics"]["inference_ms"], 20)
        self.assertEqual(output["metadata"]["referenceImageProvider"], "qwen_image_21_turbo")

    def test_invalid_model_result_never_succeeds(self):
        def invoke(_, data):
            return {**generated(data), "modelBase64": base64.b64encode(b"not glb").decode()}

        with self.assertRaises(WorkerError):
            execute_pipeline(payload(), invoke)


if __name__ == "__main__":
    unittest.main()

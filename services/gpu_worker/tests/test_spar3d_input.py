"""CPU regressions for Qwen RGBA inputs; no model or Modal calls are executed."""

import importlib.util
import sys
import unittest
from pathlib import Path


@unittest.skipUnless(importlib.util.find_spec("modal") and importlib.util.find_spec("PIL"), "Optional Modal/Pillow dependencies are not installed")
class SparInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PIL import Image

        path = Path(__file__).resolve().parents[1] / "modal_spar3d.py"
        spec = importlib.util.spec_from_file_location("spar_input_contract", path)
        cls.runtime = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.runtime
        spec.loader.exec_module(cls.runtime)
        cls.Image = Image

    def test_nearly_opaque_qwen_alpha_still_needs_segmentation(self):
        image = self.Image.new("RGBA", (20, 20), (255, 255, 255, 248))
        self.assertTrue(self.runtime._needs_background_removal(image))

    def test_opaque_input_needs_segmentation(self):
        image = self.Image.new("RGBA", (20, 20), (255, 255, 255, 255))
        self.assertTrue(self.runtime._needs_background_removal(image))

    def test_real_cutout_preserves_alpha(self):
        image = self.Image.new("RGBA", (20, 20), (0, 0, 0, 0))
        image.paste((255, 0, 0, 255), (5, 5, 15, 15))
        self.assertFalse(self.runtime._needs_background_removal(image))
        metadata = self.runtime._mask_metadata(image)
        self.assertEqual(metadata["foregroundBounds"], (5, 5, 15, 15))
        self.assertEqual(metadata["transparentFraction"], 0.75)

    def test_single_transparent_pixel_does_not_fake_a_cutout(self):
        image = self.Image.new("RGBA", (20, 20), (255, 255, 255, 255))
        image.putpixel((0, 0), (0, 0, 0, 0))
        self.assertTrue(self.runtime._needs_background_removal(image))

    def test_empty_mask_exposes_no_foreground(self):
        metadata = self.runtime._mask_metadata(self.Image.new("RGBA", (20, 20), (0, 0, 0, 0)))
        self.assertEqual(metadata["foregroundFraction"], 0)
        self.assertIsNone(metadata["foregroundBounds"])


if __name__ == "__main__":
    unittest.main()

"""Tests for the hardware-detection module — runs without fastapi installed."""

import unittest

from solstream_webui import detect


class TestDetect(unittest.TestCase):
    def test_snapshot_returns_dict_with_all_keys(self):
        s = detect.snapshot()
        for key in ("hostname", "lan_ip", "os", "kernel", "gpu",
                    "secure_boot", "cpu", "memory_gb", "disks"):
            self.assertIn(key, s, f"missing key: {key}")

    def test_gpu_dict_has_vendor_and_model(self):
        s = detect.snapshot()
        self.assertIn("vendor", s["gpu"])
        self.assertIn("model", s["gpu"])

    def test_urls_returns_https_endpoints(self):
        urls = detect.urls()
        self.assertIn("sunshine_web_ui", urls)
        self.assertTrue(urls["sunshine_web_ui"].startswith("https://"))
        self.assertIn(":47990", urls["sunshine_web_ui"])

    def test_memory_gb_is_reasonable(self):
        s = detect.snapshot()
        self.assertIsInstance(s["memory_gb"], float)
        # >0 on a real machine, may be 0 in CI containers
        self.assertGreaterEqual(s["memory_gb"], 0)


if __name__ == "__main__":
    unittest.main()

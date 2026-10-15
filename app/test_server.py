import json
import os
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent


class ServerSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        env = os.environ.copy()
        env["PORT"] = "18080"
        env["AWS_REGION"] = "local"
        cls.proc = subprocess.Popen(
            [sys.executable, str(APP_DIR / "server.py")],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        cls.base = "http://127.0.0.1:18080"
        for _ in range(40):
            try:
                urllib.request.urlopen(cls.base + "/health", timeout=0.3)
                break
            except Exception:
                time.sleep(0.1)
        else:
            raise RuntimeError("Local server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        try:
            cls.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            cls.proc.kill()

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=2) as response:
            return response.status, response.read().decode()

    def test_health(self):
        status, body = self.get("/health")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["status"], "ok")

    def test_readiness(self):
        status, body = self.get("/health/ready")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["status"], "ok")

    def test_status_endpoint(self):
        status, body = self.get("/api/status")
        data = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(data["status"], "ok")
        self.assertIn("instance_requests", data)
        self.assertIn("uptime_seconds", data)

    def test_homepage_contains_dashboard(self):
        status, body = self.get("/")
        self.assertEqual(status, 200)
        self.assertIn("CloudPulse", body)
        self.assertIn("CLOUDPULSE_INITIAL", body)

    def test_static_assets(self):
        status, css = self.get("/dashboard.css")
        self.assertEqual(status, 200)
        self.assertIn("font-family", css)
        status, js = self.get("/dashboard.js")
        self.assertEqual(status, 200)
        self.assertIn("setInterval", js)

    def test_unknown_route(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(self.base + "/not-found", timeout=2)
        self.assertEqual(ctx.exception.code, 404)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Small standard-library HTTP dashboard server for the AWS HA capstone."""
from __future__ import annotations

import json
import logging
import os
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

APP_DIR = Path(__file__).resolve().parent
PORT = int(os.getenv("PORT", "8080"))
BUILD_VERSION = os.getenv("APP_BUILD_VERSION", "1.0.0")
REGION = os.getenv("AWS_REGION", "local")
STARTED_AT = time.time()
INSTANCE_REQUESTS = 0
LOCAL_VISITS = 0
COUNTER_LOCK = threading.Lock()
LOG = logging.getLogger("cloudpulse")


def instance_metadata(path: str) -> str:
    """Read EC2 metadata with IMDSv2; return a local-safe fallback."""
    token = ""
    try:
        req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            data=b"",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
            method="PUT",
        )
        with urllib.request.urlopen(req, timeout=0.4) as response:
            token = response.read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        with urllib.request.urlopen(req, timeout=0.4) as response:
            return response.read().decode().strip()
    except Exception:
        return "local" if REGION == "local" else "unavailable"


def increment_global_counter() -> tuple[int | None, str | None]:
    """Invoke the configured Lambda function, or use local counter outside AWS."""
    global LOCAL_VISITS
    function_name = os.getenv("COUNTER_FUNCTION_NAME", "")
    if not function_name:
        with COUNTER_LOCK:
            LOCAL_VISITS += 1
            return LOCAL_VISITS, None
    try:
        import boto3  # Imported only when deployed with AWS counter configured.
        from botocore.config import Config
        client = boto3.client("lambda", config=Config(connect_timeout=2, read_timeout=5, retries={"max_attempts": 1}))
        response = client.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
            Payload=json.dumps({"action": "increment", "counter_id": "homepage"}).encode(),
        )
        payload = json.loads(response["Payload"].read().decode() or "{}")
        if response.get("FunctionError") or payload.get("statusCode", 200) >= 400:
            return None, "Counter temporarily unavailable"
        body = payload.get("body", "{}")
        body = json.loads(body) if isinstance(body, str) else body
        return int(body["visits"]), None
    except Exception as exc:
        LOG.warning("Counter invocation failed: %s", type(exc).__name__)
        return None, "Counter temporarily unavailable"


def read_global_counter() -> tuple[int | None, str | None]:
    """Read the shared counter without creating another page request."""
    global LOCAL_VISITS
    function_name = os.getenv("COUNTER_FUNCTION_NAME", "")
    if not function_name:
        with COUNTER_LOCK:
            return LOCAL_VISITS, None
    try:
        import boto3
        from botocore.config import Config
        client = boto3.client("lambda", config=Config(connect_timeout=2, read_timeout=5, retries={"max_attempts": 1}))
        response = client.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
            Payload=json.dumps({"action": "get", "counter_id": "homepage"}).encode(),
        )
        payload = json.loads(response["Payload"].read().decode() or "{}")
        if response.get("FunctionError") or payload.get("statusCode", 200) >= 400:
            return None, "Counter temporarily unavailable"
        body = payload.get("body", "{}")
        body = json.loads(body) if isinstance(body, str) else body
        return int(body["visits"]), None
    except Exception as exc:
        LOG.warning("Counter read failed: %s", type(exc).__name__)
        return None, "Counter temporarily unavailable"


def status_payload() -> dict[str, Any]:
    with COUNTER_LOCK:
        instance_requests = INSTANCE_REQUESTS
    return {
        "status": "ok",
        "instance_id": instance_metadata("instance-id"),
        "availability_zone": instance_metadata("placement/availability-zone"),
        "region": os.getenv("AWS_REGION", REGION),
        "uptime_seconds": max(0, int(time.time() - STARTED_AT)),
        "instance_requests": instance_requests,
        "build_version": BUILD_VERSION,
        "hostname": socket.gethostname(),
        "timestamp": int(time.time()),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "CloudPulse"
    sys_version = ""

    def send_bytes(self, data: bytes, content_type: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        global INSTANCE_REQUESTS
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self.send_bytes(b'{"status":"ok"}', "application/json")
            return
        if path == "/health/ready":
            # The shared counter is optional for serving the dashboard; readiness
            # reports process health and leaves dependency failures visible in UI.
            self.send_bytes(b'{"status":"ready"}', "application/json")
            return
        if path == "/api/status":
            self.send_bytes(json.dumps(status_payload()).encode(), "application/json")
            return
        if path == "/api/visits":
            visits, error = read_global_counter()
            self.send_bytes(json.dumps({
                "available": visits is not None,
                "visits": visits,
                "error": error,
                "timestamp": int(time.time()),
            }).encode(), "application/json")
            return
        if path in ("/dashboard.css", "/dashboard.js"):
            asset = APP_DIR / path.lstrip("/")
            if asset.is_file():
                content_type = "text/css; charset=utf-8" if path.endswith(".css") else "application/javascript; charset=utf-8"
                self.send_bytes(asset.read_bytes(), content_type)
                return
            self.send_bytes(b'{"error":"not found"}', "application/json", 404)
            return
        if path == "/":
            with COUNTER_LOCK:
                INSTANCE_REQUESTS += 1
            visits, error = increment_global_counter()
            html = (APP_DIR / "dashboard.html").read_text(encoding="utf-8")
            data = {
                "visits": visits,
                "counter_error": error,
                "build_version": BUILD_VERSION,
                "region": os.getenv("AWS_REGION", REGION),
            }
            html = html.replace("__INITIAL_DATA__", json.dumps(data).replace("</", "<\\/"))
            self.send_bytes(html.encode(), "text/html; charset=utf-8")
            return
        self.send_bytes(b'{"error":"not found"}', "application/json", 404)

    def do_HEAD(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/health", "/health/ready"):
            body = b'{"status":"ok"}' if path == "/health" else b'{"status":"ready"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, fmt: str, *args: Any) -> None:
        print(json.dumps({"level": "INFO", "client": self.client_address[0], "message": fmt % args}))


if __name__ == "__main__":
    print(f"Starting dashboard on 0.0.0.0:{PORT} build={BUILD_VERSION}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

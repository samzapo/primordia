#!/usr/bin/env python3
"""Primordia browser assets, bounded WebSocket relay and read-only health."""
import ipaddress
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import select
import socket
import subprocess
import time
import threading
from urllib.parse import urlsplit

def home_urls(port):
    result = []
    entries = json.loads(subprocess.check_output(["ip", "-j", "addr"], text=True))
    for interface in entries:
        if not (Path("/sys/class/net") / interface["ifname"] / "device").exists():
            continue
        for address in interface.get("addr_info", []):
            if address.get("family") != "inet":
                continue
            value = ipaddress.ip_address(address["local"])
            if value.is_private and not value.is_loopback and not value.is_link_local:
                result.append(f"http://{value}:{port}")
    return sorted(set(result))

class Gateway(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    slots = threading.BoundedSemaphore(32)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        request.settimeout(15)
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(args[2].web_root), **kwargs)

    def log_message(self, *args):
        pass  # No request URLs, credentials or client messages enter logs.

    def list_directory(self, path):
        self.send_error(404)
        return None

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def json_response(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/ws":
            return self.websocket()
        if path in {"/health", "/metrics"}:
            try:
                value = json.loads((self.server.state / "health.json").read_text())
                stale = time.time() - value.get("updated_unix", 0) > 20
                self.json_response(value, 503 if stale else 200)
            except (OSError, ValueError):
                self.json_response({"status": "starting"}, 503)
            return
        if path == "/api/network":
            self.json_response({"home_urls": home_urls(self.server.server_port)})
            return
        super().do_GET()

    def websocket(self):
        self.close_connection = True
        if self.headers.get("Upgrade", "").lower() != "websocket":
            self.send_error(400)
            return
        origin = self.headers.get("Origin")
        if origin and urlsplit(origin).netloc != self.headers.get("Host"):
            self.send_error(403)
            return
        try:
            upstream = socket.create_connection(("127.0.0.1", self.server.world_port), timeout=5)
        except OSError:
            self.send_error(503)
            return
        with upstream:
            headers = f"GET /ws HTTP/1.1\r\n" + "".join(
                f"{name}: {value}\r\n" for name, value in self.headers.items()
                if name.lower() not in {"proxy-connection", "connection"})
            upstream.sendall((headers + "Connection: Upgrade\r\n\r\n").encode("latin-1"))
            endpoints = (self.connection, upstream)
            for stream in endpoints:
                stream.setblocking(False)
            pending = {self.connection: bytearray(), upstream: bytearray()}
            active = time.monotonic()
            try:
                while time.monotonic() - active < 60:
                    readable, writable, _ = select.select(
                        endpoints, [stream for stream in endpoints if pending[stream]], [], 1)
                    for stream in readable:
                        block = stream.recv(65536)
                        if not block:
                            return
                        other = upstream if stream is self.connection else self.connection
                        pending[other].extend(block)
                        if len(pending[other]) > 2 * 1024 * 1024:
                            return
                        active = time.monotonic()
                    for stream in writable:
                        sent = stream.send(pending[stream])
                        del pending[stream][:sent]
            except (OSError, ConnectionError):
                return

def create(web_root, state, port=8766, world_port=8767, bind="0.0.0.0"):
    service = Gateway((bind, port), Handler)
    service.web_root = Path(web_root)
    service.state = Path(state)
    service.world_port = world_port
    Handler.extensions_map[".wasm"] = "application/wasm"
    return service

#!/usr/bin/env python3
"""Primordia browser assets, bounded WebSocket relay and read-only health."""
import ipaddress
import html
import ssl
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import select
import socket
import subprocess
import time
import threading
from urllib.parse import urlsplit

def home_urls(port, secure=False):
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
                result.append(f"{'https' if secure else 'http'}://{value}:{port}")
    return sorted(set(result))

class Gateway(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(32)
        self.tls_directory = None
        self.tls_context = None
        super().__init__(*args, **kwargs)

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
            # Classify in a bounded worker, so stalled TLS handshakes cannot block accept().
            # The same port retains a plain HTTP certificate setup page and loopback health.
            if self.tls_context and request.recv(1, socket.MSG_PEEK) == b"\x16":
                request.settimeout(5)
                request = self.tls_context.wrap_socket(request, server_side=True)
                request.settimeout(15)
            super().process_request_thread(request, address)
        except (OSError, ssl.SSLError):
            self.shutdown_request(request)
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

    def send_head(self):
        self.serving_asset = True
        try:
            return super().send_head()
        finally:
            self.serving_asset = False

    def end_headers(self):
        if not self.server.tls_context or isinstance(self.connection, ssl.SSLSocket):
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        if getattr(self, "serving_asset", False):
            # Revalidate unversioned page/runtime URLs; unchanged large files can return 304.
            self.send_header("Cache-Control", "no-cache")
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
        if path == "/ca.crt" and self.server.tls_directory:
            data = (self.server.tls_directory / "authority/ca.crt").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-x509-ca-cert")
            self.send_header("Content-Disposition", 'attachment; filename="primordia-lan-ca.crt"')
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
            return
        if self.server.tls_context and not isinstance(self.connection, ssl.SSLSocket) and path not in {"/health", "/metrics", "/api/network"}:
            if path == "/ws":
                self.send_error(426, "Use the HTTPS game address and secure WebSocket")
                return
            return self.certificate_setup()
        if path == "/setup" and self.server.tls_directory:
            return self.certificate_setup()
        if path == "/ws":
            return self.websocket()
        if path in {"/health", "/metrics"}:
            try:
                value = json.loads((self.server.state / "health.json").read_text())
                stale = time.time() - value.get("updated_unix", 0) > 20 or bool(value.get("backend_error")) or bool(value.get("checkpoint_error"))
                self.json_response(value, 503 if stale else 200)
            except (OSError, ValueError):
                self.json_response({"status": "starting"}, 503)
            return
        if path == "/api/network":
            self.json_response({"home_urls": home_urls(self.server.server_port, bool(self.server.tls_context))})
            return
        super().do_GET()

    def do_HEAD(self):
        if self.server.tls_context and not isinstance(self.connection, ssl.SSLSocket):
            self.send_error(426, "Use HTTPS for game assets")
            return
        super().do_HEAD()

    def certificate_setup(self):
        from lan_tls import fingerprint
        host = html.escape(self.headers.get("Host", ""), quote=True)
        digest = html.escape(fingerprint(self.server.tls_directory))
        page = f"""<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Primordia HTTPS setup</title>
<style>body{{font:18px/1.5 system-ui,sans-serif;background:#162b36;color:#e9f4f3;max-width:44rem;margin:3rem auto;padding:1.5rem}}a{{color:#9ef0c9}}code{{overflow-wrap:anywhere}}li{{margin:1rem 0}}</style>
<h1>Primordia HTTPS setup</h1><p>The game uses HTTPS on this same port. This private address needs one certificate installation on each device.</p>
<ol><li><a href="/ca.crt" download="primordia-lan-ca.crt">Download Primordia's LAN CA certificate</a>.</li>
<li>On Android, open Settings and search for <strong>Install a certificate</strong>. Choose <strong>CA certificate</strong> and select <code>primordia-lan-ca.crt</code>. Depending on the phone, this is under Security &amp; privacy, More security settings, or Encryption &amp; credentials.</li>
<li><a href="https://{host}/">Open Primordia securely</a>. Enter your private invitation when the game opens.</li></ol>
<p>This certificate is constrained to private IP addresses and localhost. Its signing key stays on the game server. The installation is separate from accepting a browser certificate warning.</p>
<p>To remove it later, find Primordia Private LAN CA in your device's user-installed trusted credentials.</p>
<p>CA SHA-256 fingerprint: <code>{digest}</code></p></html>""".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(page)

    def websocket(self):
        self.close_connection = True
        if self.headers.get("Upgrade", "").lower() != "websocket":
            self.send_error(400)
            return
        origin = self.headers.get("Origin")
        forwarded_tls = (self.server.trusted_proxy and ipaddress.ip_address(self.client_address[0]).is_loopback
                         and self.headers.get("X-Forwarded-Proto", "") == "https")
        expected_scheme = "https" if isinstance(self.connection, ssl.SSLSocket) or forwarded_tls else "http"
        if origin and (urlsplit(origin).netloc != self.headers.get("Host") or urlsplit(origin).scheme != expected_scheme):
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
            reading = list(endpoints)
            ended = False
            try:
                while time.monotonic() - active < 60:
                    if ended and not any(pending.values()):
                        return
                    buffered = [stream for stream in reading if isinstance(stream, ssl.SSLSocket) and stream.pending()]
                    readable, writable, _ = select.select(
                        reading, [stream for stream in endpoints if pending[stream]], [], 0 if buffered else 1)
                    for stream in set(readable + buffered):
                        try:
                            block = stream.recv(65536)
                        except (BlockingIOError, ssl.SSLWantReadError, ssl.SSLWantWriteError):
                            continue
                        if not block:
                            reading.remove(stream)
                            ended = True
                            continue  # Drain accepted bytes before closing the relay.
                        other = upstream if stream is self.connection else self.connection
                        pending[other].extend(block)
                        if len(pending[other]) > 2 * 1024 * 1024:
                            return
                        active = time.monotonic()
                    for stream in writable:
                        try:
                            sent = stream.send(pending[stream])
                        except (BlockingIOError, ssl.SSLWantReadError, ssl.SSLWantWriteError):
                            continue
                        del pending[stream][:sent]
            except (OSError, ConnectionError):
                return

def create(web_root, state, port=8766, world_port=8767, bind="0.0.0.0", tls_directory=None, trusted_proxy=False):
    if trusted_proxy and not ipaddress.ip_address(bind).is_loopback:
        raise ValueError("Proxy trust requires a loopback-only gateway")
    service = Gateway((bind, port), Handler)
    service.trusted_proxy = trusted_proxy
    service.web_root = Path(web_root)
    service.state = Path(state)
    service.world_port = world_port
    if tls_directory is not None:
        from lan_tls import provision
        service.tls_directory = Path(tls_directory)
        service.tls_context = provision(service.tls_directory)
    Handler.extensions_map[".wasm"] = "application/wasm"
    return service

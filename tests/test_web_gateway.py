#!/usr/bin/env python3
"""Exercise real trusted LAN TLS, HTTP bootstrap and encrypted duplex transport."""
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import ssl
import sys
import tempfile
import threading
import time
import unittest
from urllib.request import build_opener, HTTPSHandler, ProxyHandler, Request
from urllib.error import URLError, HTTPError
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lan_tls import provision, command
from web_gateway import create


class LanGateway(unittest.TestCase):
    def test_trusted_https_and_secure_relay(self):
        with tempfile.TemporaryDirectory(prefix="primordia-lan-tls-") as scratch:
            root = Path(scratch)
            web = root / "web"; web.mkdir()
            (web / "index.html").write_text("actual game asset")
            state = root / "state"; state.mkdir()
            (state / "health.json").write_text(json.dumps({"updated_unix":time.time(), "tick":123}))
            tls = root / "tls"
            provision(tls, ["127.0.0.1", "::1"])
            ca = (tls / "authority/ca.crt").read_bytes()
            initial = (tls / "current").resolve()
            provision(tls, ["127.0.0.1", "::1"])
            self.assertEqual(initial, (tls / "current").resolve())
            self.assertEqual(ca, (tls / "authority/ca.crt").read_bytes())
            self.assertEqual((tls / "authority/ca.key").stat().st_mode & 0o777, 0o600)
            self.assertEqual((tls / "current/server.key").stat().st_mode & 0o777, 0o600)
            upstream = socket.socket(); upstream.bind(("127.0.0.1",0)); upstream.listen()
            payload = b"finite-authoritative-snapshot" * 18000
            received = []
            failures = []
            def world():
                try:
                    connection, _ = upstream.accept()
                    with connection:
                        connection.settimeout(10)
                        request = b""
                        while not request.endswith(b"\r\n\r\n"): request += connection.recv(1)
                        self.assertIn(b"GET /ws HTTP/1.1", request)
                        connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
                        data = b""
                        while len(data) < len(payload): data += connection.recv(min(65536,len(payload)-len(data)))
                        received.append(data)
                        connection.sendall(data)
                except BaseException as error: failures.append(error)
            world_thread = threading.Thread(target=world, daemon=True); world_thread.start()
            service = create(web, state, 0, upstream.getsockname()[1], bind="127.0.0.1", tls_directory=tls)
            worker = threading.Thread(target=service.serve_forever, daemon=True); worker.start()
            port = service.server_port
            context = ssl.create_default_context(cafile=str(tls / "authority/ca.pem"))
            trusted = build_opener(ProxyHandler({}), HTTPSHandler(context=context))
            plain = build_opener(ProxyHandler({}))
            try:
                with plain.open(f"http://127.0.0.1:{port}/", timeout=5) as response:
                    bootstrap = response.read()
                self.assertIn(b"Primordia HTTPS setup", bootstrap)
                self.assertNotIn(b"actual game asset", bootstrap)
                with plain.open(f"http://127.0.0.1:{port}/ca.crt", timeout=5) as response:
                    self.assertEqual(response.read(), ca)
                with trusted.open(f"https://127.0.0.1:{port}/", timeout=5) as response:
                    self.assertEqual(response.read(), b"actual game asset")
                    self.assertEqual(response.headers["Cross-Origin-Opener-Policy"], "same-origin")
                    self.assertEqual(response.headers["Cache-Control"], "no-cache")
                    modified = response.headers["Last-Modified"]
                # A reload can reuse unchanged engine data, but must see replaced client files.
                try:
                    trusted.open(Request(f"https://127.0.0.1:{port}/", headers={"If-Modified-Since":modified}), timeout=5)
                    self.fail("Unchanged asset should be revalidated with 304")
                except HTTPError as error:
                    self.assertEqual(error.code,304)
                    self.assertEqual(error.headers["Cache-Control"], "no-cache")
                    error.close()
                (web / "index.html").write_text("updated game asset")
                import os
                changed = (web / "index.html").stat().st_mtime + 2
                os.utime(web / "index.html", (changed,changed))
                with trusted.open(Request(f"https://127.0.0.1:{port}/", headers={"If-Modified-Since":modified}), timeout=5) as response:
                    self.assertEqual(response.read(), b"updated game asset")
                    self.assertEqual(response.headers["Cache-Control"], "no-cache")
                with trusted.open(f"https://127.0.0.1:{port}/health", timeout=5) as response:
                    self.assertEqual(json.load(response)["tick"], 123)
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                with trusted.open(f"https://127.0.0.1:{port}/api/network", timeout=5) as response:
                    self.assertTrue(all(url.startswith("https://") for url in json.load(response)["home_urls"]))
                with self.assertRaises(URLError):
                    plain.open(f"https://127.0.0.1:{port}/", timeout=5)
                with socket.create_connection(("127.0.0.1",port),timeout=5) as raw:
                    with self.assertRaises(ssl.SSLCertVerificationError):
                        context.wrap_socket(raw,server_hostname="public.example")
                # A matching public DNS SAN still fails CA name constraints, independently of hostname matching.
                command("req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                        "-nodes", "-subj", "/CN=public.example", "-keyout", root/"forbidden.key", "-out", root/"forbidden.csr")
                (root/"forbidden.cnf").write_text("basicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:public.example\n")
                command("x509", "-req", "-in", root/"forbidden.csr", "-CA", tls/"authority/ca.pem",
                        "-CAkey", tls/"authority/ca.key", "-set_serial", "5", "-days", "1", "-extfile", root/"forbidden.cnf", "-out", root/"forbidden.pem")
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    command("verify", "-CAfile", tls/"authority/ca.pem", "-verify_hostname", "public.example", root/"forbidden.pem")
                self.assertIn(b"permitted subtree violation",failure.exception.stderr)
                public = root / "public"
                provision(public, ["127.0.0.1"])
                wrong_ca = ssl.create_default_context(cafile=str(public / "authority/ca.pem"))
                with socket.create_connection(("127.0.0.1",port),timeout=5) as raw:
                    with self.assertRaises(ssl.SSLCertVerificationError):
                        wrong_ca.wrap_socket(raw,server_hostname="127.0.0.1")
                try:
                    plain.open(f"http://127.0.0.1:{port}/ws",timeout=5)
                    self.fail("Insecure WebSocket accepted")
                except HTTPError as error:
                    self.assertEqual(error.code,426)
                    error.close()
                try:
                    trusted.open(Request(f"https://127.0.0.1:{port}/ws", headers={"Upgrade":"websocket", "Origin":f"http://127.0.0.1:{port}"}),timeout=5)
                    self.fail("Insecure browser origin accepted over WSS")
                except HTTPError as error:
                    self.assertEqual(error.code,403)
                    error.close()
                with context.wrap_socket(socket.create_connection(("127.0.0.1",port),timeout=10),server_hostname="127.0.0.1") as client:
                    client.sendall(f"GET /ws HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nOrigin: https://127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: fixture\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
                    handshake = b""
                    while not handshake.endswith(b"\r\n\r\n"): handshake += client.recv(1)
                    self.assertIn(b"101 Switching Protocols",handshake)
                    client.sendall(payload)
                    echoed = b""
                    while len(echoed)<len(payload):
                        part=client.recv(65536)
                        self.assertTrue(part,"Encrypted snapshot was truncated")
                        echoed+=part
                    self.assertEqual(hashlib.sha256(echoed).digest(),hashlib.sha256(payload).digest())
                world_thread.join(timeout=10)
                self.assertFalse(world_thread.is_alive())
                self.assertFalse(failures, failures)
                self.assertEqual(received,[payload])
            finally:
                service.shutdown(); service.server_close(); upstream.close(); worker.join(timeout=5)


if __name__ == "__main__": unittest.main()

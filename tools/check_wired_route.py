#!/usr/bin/env python3
"""Verify effective physical wired routes before Primordia bulk downloads."""
import json
import os
from pathlib import Path
import socket
import subprocess
from urllib.parse import urlsplit

HOSTS = ("github.com", "api.github.com", "raw.githubusercontent.com",
         "objects.githubusercontent.com", "release-assets.githubusercontent.com")

def verify(hosts=HOSTS):
    peers = set(hosts)
    for key in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"):
        proxy = os.environ.get(key)
        if proxy:
            host = urlsplit(proxy).hostname
            if not host:
                raise RuntimeError("Cannot resolve transfer proxy transport")
            peers.add(host)
    for host in sorted(peers):
        wired = set()
        for entry in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM):
            address = entry[4][0]
            value = subprocess.run(["ip", "-j", "route", "get", address],
                                   capture_output=True, text=True)
            if value.returncode:
                continue
            routes = json.loads(value.stdout)
            for route in routes:
                interface = route.get("dev", "")
                path = Path("/sys/class/net") / interface
                if (not interface or not (path / "device").exists()
                        or (path / "wireless").exists() or (path / "phy80211").exists()
                        or (path / "operstate").read_text().strip() != "up"):
                    raise RuntimeError(f"No verified active wired route to {host}: {interface}")
                wired.add(interface)
        if not wired:
            raise RuntimeError(f"No reachable wired address for {host}")
        print(f"Wired route: {host} via {', '.join(sorted(wired))}", flush=True)

if __name__ == "__main__":
    verify()

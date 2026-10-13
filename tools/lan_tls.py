#!/usr/bin/env python3
"""Retained, private-address-constrained CA and automatically renewed LAN TLS."""
import ipaddress
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile


def command(*args):
    return subprocess.check_output(["openssl", *map(str, args)], stderr=subprocess.PIPE)


def physical_addresses():
    addresses = {"127.0.0.1", "::1"}
    for interface in json.loads(subprocess.check_output(["ip", "-j", "addr"], text=True)):
        device = Path("/sys/class/net") / interface["ifname"]
        if not (device / "device").exists():
            continue
        for item in interface.get("addr_info", []):
            value = ipaddress.ip_address(item["local"])
            if value.version == 4 and value.is_private and not value.is_link_local:
                addresses.add(str(value))
    return sorted(addresses)


def provision(directory, addresses=None):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    authority = directory / "authority"
    if not authority.exists():
        temporary = Path(tempfile.mkdtemp(prefix="authority-", dir=directory))
        try:
            command("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                    "-nodes", "-sha256", "-days", "3650", "-subj", "/CN=Primordia Private LAN CA",
                    "-addext", "basicConstraints=critical,CA:TRUE,pathlen:0",
                    "-addext", "keyUsage=critical,keyCertSign,cRLSign",
                    "-addext", "nameConstraints=critical,permitted;IP:10.0.0.0/255.0.0.0,permitted;IP:172.16.0.0/255.240.0.0,permitted;IP:192.168.0.0/255.255.0.0,permitted;IP:127.0.0.0/255.0.0.0,permitted;IP:0:0:0:0:0:0:0:1/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff,permitted;DNS:localhost",
                    "-keyout", temporary / "ca.key", "-out", temporary / "ca.pem")
            (temporary / "ca.key").chmod(0o600)
            command("x509", "-in", temporary / "ca.pem", "-outform", "DER", "-out", temporary / "ca.crt")
            temporary.rename(authority)
        finally:
            if temporary.exists(): shutil.rmtree(temporary)
    # Existing incomplete/invalid authority is an operator error, never silently replace phone trust.
    command("x509", "-in", authority / "ca.pem", "-checkend", "2592000", "-noout")
    if not (authority / "ca.key").is_file() or not (authority / "ca.crt").is_file():
        raise RuntimeError("Existing Primordia CA is incomplete; retain and repair its files")
    (authority / "ca.key").chmod(0o600)
    if command("pkey", "-in", authority / "ca.key", "-pubout") != command("x509", "-in", authority / "ca.pem", "-pubkey", "-noout"):
        raise RuntimeError("Retained Primordia CA key does not match its certificate")
    addresses = sorted(set(addresses or physical_addresses()))
    # Validate authored/test arguments before placing them into OpenSSL configuration.
    for value in addresses:
        if not ipaddress.ip_address(value).is_private:
            raise ValueError("Primordia LAN certificates require private addresses")
    current = directory / "current"
    renew = True
    if current.exists() and not current.is_symlink():
        raise RuntimeError("Existing TLS current path is not an owned generation link")
    if current.is_symlink():
        existing = current.resolve()
        if json.loads((existing / "addresses.json").read_text()) == addresses:
            try:
                command("x509", "-in", existing / "server.pem", "-checkend", "2592000", "-noout")
                renew = False
            except subprocess.CalledProcessError:
                pass
    if renew:
        generation = Path(tempfile.mkdtemp(prefix="server-", dir=directory))
        try:
            command("req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                    "-nodes", "-subj", "/CN=Primordia LAN server",
                    "-keyout", generation / "server.key", "-out", generation / "request.pem")
            (generation / "server.key").chmod(0o600)
            extensions = generation / "extensions.cnf"
            extensions.write_text("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost," + ",".join("IP:" + value for value in addresses) + "\n")
            command("x509", "-req", "-in", generation / "request.pem", "-CA", authority / "ca.pem",
                    "-CAkey", authority / "ca.key", "-set_serial", "0x" + os.urandom(16).hex(),
                    "-days", "365", "-sha256", "-extfile", extensions, "-out", generation / "server.pem")
            (generation / "addresses.json").write_text(json.dumps(addresses))
            command("verify", "-CAfile", authority / "ca.pem", "-purpose", "sslserver", generation / "server.pem")
            # Validate the pair before publishing the generation.
            validation = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            validation.load_cert_chain(generation / "server.pem", generation / "server.key")
            pending = directory / "current.next"
            pending.unlink(missing_ok=True)
            pending.symlink_to(generation.name)
            pending.replace(current)
        except BaseException:
            shutil.rmtree(generation)
            raise
    command("verify", "-CAfile", authority / "ca.pem", "-purpose", "sslserver", current / "server.pem")
    if command("x509", "-in", authority / "ca.pem", "-outform", "DER") != (authority / "ca.crt").read_bytes():
        raise RuntimeError("Retained Primordia CA download does not match its authority")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(current / "server.pem", current / "server.key")
    return context


def fingerprint(directory):
    value = command("x509", "-in", Path(directory) / "authority/ca.pem", "-fingerprint", "-sha256", "-noout")
    return value.decode().strip().split("=", 1)[1]

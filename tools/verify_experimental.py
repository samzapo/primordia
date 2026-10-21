#!/usr/bin/env python3
"""Verify independent saved-world and same-origin public experimental delivery."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import time
from urllib.request import build_opener,ProxyHandler,HTTPSHandler,Request
from urllib.error import HTTPError
from urllib.parse import urlsplit
from experimental_instance import stable_identity,guard,health,UNIT

def music_manifest(value):
    filename=value.get("file","")
    size=value.get("bytes")
    if not isinstance(filename,str) or not re.fullmatch(r"music-bank-[a-f0-9]{24}[.]bin",filename) or type(size) is not int or not 0<size<4*1024*1024:
        raise ValueError("Invalid music asset manifest")
    return filename,size
def pond_source(record,stable_world):
    copy=record.get("pond_copy")
    policy=record.get("pond_policy","copy-main")
    retained=record.get("pond_retention")
    assert record["feedback_retained"] and record["initial"]["cell_retention"]["ok"]
    if policy=="retain":
        assert copy is None and retained["generations_unchanged_before_start"]
        assert record["initial"]["world_id"]==retained["world_id"]!=stable_world
        assert record["initial"]["epoch"]>retained["previous_epoch"]
        assert record["initial"]["cell_retention"]["before_digest"]==retained["cells_digest"]
        source=retained
    else:
        assert policy=="copy-main" and copy["graph_unchanged"] and copy["source_world_id"]==stable_world
        assert copy["world_id"]!=stable_world
        assert record["initial"]["cell_retention"]["before_digest"]==copy["cells_digest"]
        source=copy
    return source

def main(restart=False):
    if os.environ.get("RUNNER_NAME")!="samzapo-desktop":raise RuntimeError("Wrong target")
    os.environ.setdefault("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")
    root=Path.home()/".local/share/primordia-experimental"
    stable=Path.home()/".local/share/primordia-deploy"
    baseline=stable_identity(stable)
    record=json.loads((root/"last-deploy.json").read_text())
    expected=os.environ.get("GITHUB_SHA",record["revision"])
    assert expected==record["revision"]
    copy=record.get("pond_copy")
    policy=record.get("pond_policy","copy-main")
    retained=record.get("pond_retention")
    source=pond_source(record,baseline["world_id"])
    before=health(expected,baseline["world_id"])
    assert before["world_id"]==source["world_id"] and before["tick"]>=source["source_tick"]
    if restart:
        subprocess.run(["systemctl","--user","restart",UNIT],check=True)
        after=health(expected,baseline["world_id"],before)
    else:after=before
    private=build_opener(ProxyHandler({}))
    with private.open("http://127.0.0.1:2019/config/",timeout=5) as response:config=json.load(response)
    listeners=[at for server in config["apps"]["http"]["servers"].values() for at in server.get("listen",[]) if at.endswith(":8766")]
    assert len(listeners)==1
    authority=listeners[0];base="https://"+authority
    public=build_opener(ProxyHandler({}),HTTPSHandler(context=ssl.create_default_context()))
    deliveries={}
    for prefix,sha,world,web in [("",baseline["build"],baseline["world_id"],stable/"current/build/web"),("/experimental",expected,after["world_id"],root/"current/build/web")]:
        with public.open(base+prefix+"/health",timeout=10) as response:value=json.load(response)
        assert value["build"]==sha and value["world_id"]==world and value["backend"]=="gpu"
        with public.open(base+prefix+"/",timeout=10) as response:
            document=response.read().decode()
            assert response.headers.get("Cross-Origin-Opener-Policy")=="same-origin"
        manifest=json.loads(re.search(r"const GODOT_CONFIG = ([^\r\n]+);",document).group(1))
        # Match actual independently built assets, not a different host's pack hash.
        local=json.loads(re.search(r"const GODOT_CONFIG = ([^\r\n]+);",(web/"index.html").read_text()).group(1))
        assert manifest["mainPack"]==local["mainPack"]
        if prefix:
            assert manifest["persistentPaths"]==["/userfs/primordia-experimental"]
            assert 'id="primordia-instance"' in document
        assets={}
        for asset in ["index.wasm",manifest["mainPack"]]:
            with public.open(Request(base+prefix+"/"+asset,method="HEAD"),timeout=10) as response:
                size=int(response.headers["Content-Length"])
            assert size==manifest["fileSizes"][asset]
            assets[asset]=size
        with public.open(base+prefix+"/music-bank.json",timeout=10) as response:music=json.load(response)
        music_manifest(music)
        with public.open(Request(base+prefix+"/"+music["file"],method="HEAD"),timeout=10) as response:
            assert int(response.headers["Content-Length"])==music["bytes"]
        assets[music["file"]]=music["bytes"]
        url=urlsplit(base)
        def handshake(origin):
            with socket.create_connection((url.hostname,url.port),timeout=10) as raw:
                with ssl.create_default_context().wrap_socket(raw,server_hostname=url.hostname) as stream:
                    stream.sendall((f"GET {prefix}/ws HTTP/1.1\r\nHost: {authority}\r\nOrigin: {origin}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
                    data=b""
                    while not data.endswith(b"\r\n\r\n") and len(data)<65536:
                        block=stream.recv(1)
                        if not block:break
                        data+=block
                    return data.split(b"\r\n",1)[0].decode()
        assert "101" in handshake(base)
        assert "403" in handshake("https://foreign.example")
        deliveries[prefix or "/"]={"build":sha,"world_id":world,"assets":assets,"https":200,"wss":101,"foreign_origin_rejected":True}
    for suffix in ["metrics","setup","ca.crt","api/network"]:
        try:public.open(base+"/experimental/"+suffix,timeout=5);raise AssertionError("Private endpoint exposed")
        except HTTPError as error:assert error.code==404;error.close()
    time.sleep(3)
    final=guard(stable,baseline)
    assert final["tick"]>baseline["tick"]
    assert hashlib_sha(root/"access-keys.json")==hashlib_sha(stable/"access-keys.json")
    manifest=json.loads((root/"caddy-route-manifest.json").read_text())
    installed=hashlib_sha(Path("/etc/caddy/Caddyfile"))==manifest["candidate_sha256"]
    persistence="installed" if installed else record["routing"]["persistence"]
    report={"revision":expected,"experimental":after,"stable_before":baseline,"stable_after":final,
        "public_delivery":deliveries,"pond_policy":policy,"pond_copy":copy,"pond_retention":retained,"restart_tested":restart,"stable_unit_restarted":False,
        "routing_persistence":persistence,"operator_command":None if installed else record["routing"]["operator_command"],
        "scope":"Server-origin trusted HTTPS/WSS, no physical-phone claim or synthetic production sign-in/report"}
    (root/"last-verify.json").write_text(json.dumps(report,indent=2))
    print("EXPERIMENTAL_VERIFIED "+json.dumps(report))
def hashlib_sha(path):
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()
if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--restart",action="store_true")
    main(parser.parse_args().restart)

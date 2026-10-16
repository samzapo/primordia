#!/usr/bin/env python3
"""Add only Primordia's experimental path through Caddy's conditional config API."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.request import build_opener, ProxyHandler, Request
from urllib.parse import quote

API="http://127.0.0.1:2019"
MARKER="primordia-experimental"
SNIPPET='''
	# Independent experimental pond; stable requests keep their original route.
	redir /experimental /experimental/ 308
	@experimental_private path /experimental/setup /experimental/ca.crt /experimental/api/network /experimental/metrics
	respond @experimental_private 404
	handle_path /experimental/* {
		reverse_proxy 127.0.0.1:8768
	}
'''
def experimental_route():
    return {"@id":MARKER,"match":[{"path":["/experimental","/experimental/*"]}],
        "handle":[{"handler":"subroute","routes":[
            {"match":[{"path":["/experimental/setup","/experimental/ca.crt","/experimental/api/network","/experimental/metrics"]}],
             "handle":[{"handler":"static_response","status_code":404}]},
            {"match":[{"path":["/experimental"]}],"handle":[{"handler":"static_response","status_code":308,"headers":{"Location":["/experimental/"]}}]},
            {"handle":[{"handler":"rewrite","strip_path_prefix":"/experimental"},
                {"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:8768"}]}]}
        ]}],"terminal":True}
def walks(value,path=()):
    yield path,value
    if isinstance(value,dict):
        for key,item in value.items():yield from walks(item,(*path,str(key)))
    elif isinstance(value,list):
        for index,item in enumerate(value):yield from walks(item,(*path,str(index)))
def upstream(value,address):
    return any(isinstance(item,dict) and item.get("handler")=="reverse_proxy" and
        {"dial":address} in item.get("upstreams",[]) for _,item in walks(value))
def scope(config):
    matches=[]
    for name,server in config.get("apps",{}).get("http",{}).get("servers",{}).items():
        if not any(str(at).endswith(":8766") for at in server.get("listen",[])):continue
        for path,value in walks(server):
            if path and path[-1]=="routes" and isinstance(value,list):
                if any(isinstance(row,dict) and any(h.get("handler")=="reverse_proxy" and upstream(h,"127.0.0.1:8766") for h in row.get("handle",[])) for row in value):
                    matches.append((("apps","http","servers",name,*path),value))
    if len(matches)!=1:raise RuntimeError("Expected exactly one existing Primordia stable proxy scope")
    return matches[0]
def with_experimental(routes):
    for row in routes:
        if row.get("@id")==MARKER:
            if row!=experimental_route():raise RuntimeError("Experimental route was changed concurrently")
            return copy.deepcopy(routes),False
    existing=[]
    for _,item in walks(routes):
        if isinstance(item,dict):
            paths=[p for match in item.get("match",[]) for p in match.get("path",[])]
            if any(str(p).startswith("/experimental") for p in paths):existing.append((item,paths))
    if existing:
        if any("/experimental/*" in paths and upstream(item,"127.0.0.1:8768") for item,paths in existing):
            return copy.deepcopy(routes),False
        raise RuntimeError("Experimental path already belongs to a different route")
    return [experimental_route(),*copy.deepcopy(routes)],True
def caddyfile(text):
    # Find the single top-level site opening for port8766; quoted placeholders,
    # comments and nested reverse_proxy blocks cannot be mistaken for that site.
    depth=0;quoted=False;escaped=False;comment=False;line=0;openings=[]
    for i,char in enumerate(text):
        if char=="\n":comment=False;line=i+1
        if comment:continue
        if quoted:
            if escaped:escaped=False
            elif char=="\\":escaped=True
            elif char=='"':quoted=False
            continue
        if char=="#":comment=True;continue
        if char=='"':quoted=True;continue
        if char=="{":
            if depth==0 and ":8766" in text[line:i]:openings.append(i+1)
            depth+=1
        elif char=="}":depth-=1
    if len(openings)!=1 or depth!=0:raise RuntimeError("Cannot safely identify the existing Primordia Caddyfile site")
    if "handle_path /experimental/*" in text:return text
    at=openings[0]
    return text[:at]+SNIPPET+text[at:]
def prepare_and_apply(root):
    opener=build_opener(ProxyHandler({}))
    with opener.open(API+"/config/",timeout=5) as response:current=json.load(response)
    path,_=scope(current)
    endpoint=API+"/config/"+"/".join(quote(part,safe="") for part in path)
    with opener.open(endpoint,timeout=5) as response:
        routes=json.load(response);etag=response.headers.get("Etag")
    changed,needed=with_experimental(routes)
    if not etag:raise RuntimeError("Caddy config lacks concurrency protection")
    original=Path("/etc/caddy/Caddyfile").read_text()
    target=root/"Caddyfile.with-experimental"
    prepared=caddyfile(original)
    target.write_text(prepared);target.chmod(0o600)
    adapted=subprocess.run(["caddy","adapt","--config",str(target),"--adapter","caddyfile"],capture_output=True,text=True)
    if adapted.returncode:raise RuntimeError("Experimental Caddyfile failed adaptation")
    plan=json.loads(adapted.stdout)
    if not upstream(plan,"127.0.0.1:8766") or not upstream(plan,"127.0.0.1:8768"):
        raise RuntimeError("Prepared routing must preserve both upstreams")
    manifest={"original_sha256":hashlib.sha256(original.encode()).hexdigest(),
              "candidate_sha256":hashlib.sha256(prepared.encode()).hexdigest(),"candidate":str(target)}
    (root/"caddy-route-manifest.json").write_text(json.dumps(manifest,indent=2))
    if needed:
        (root/"caddy-before-experimental.json").write_text(json.dumps(current,indent=2))
        request=Request(endpoint,data=json.dumps(changed).encode(),method="PATCH",
                        headers={"Content-Type":"application/json","If-Match":etag})
        with opener.open(request,timeout=20) as response:assert response.status==200
    with opener.open(endpoint,timeout=5) as response:
        actual=json.load(response)
    assert not with_experimental(actual)[1],"Experimental route was not accepted"
    pid=subprocess.check_output(["systemctl","show","caddy","-p","MainPID","--value"],text=True).strip()
    argv=(Path("/proc")/pid/"cmdline").read_bytes().decode().split("\0")
    resume="--resume" in argv
    persistence="caddy_resume" if resume else ("already_in_caddyfile" if prepared==original else "operator_install_required")
    return {"live_route":True,"route_added":needed,"persistence":persistence,
            "caddy_resume":resume,"candidate":str(target),
            "operator_command":None if persistence!="operator_install_required" else
                "sudo python3 "+str(root/"current/tools/install_experimental_route.py")+" --root "+str(root)}

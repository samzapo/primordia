#!/usr/bin/env python3
"""Inspect vendor-served request definitions; never execute JavaScript or change SRM."""
import hashlib
from http.client import HTTPSConnection
import json
import os
import re
import secrets
import ssl
import sys
from urllib.parse import urlsplit

def fetch(path, sid=""):
    if not (path in {"/webman/index.cgi","/webman/synodefs.cgi","/synoSDSjslib/sds.js","/webman/initdata.cgi"} or re.fullmatch(r"/webman/[A-Za-z0-9_./-]+\.js",path)):
        raise ValueError("Only SRM static JavaScript and page definitions are allowed")
    url=urlsplit(path)
    if url.scheme or url.netloc or not url.path.startswith("/") or ".." in url.path or len(path)>512:
        raise ValueError("Only bounded same-router paths are allowed")
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname=False;context.verify_mode=ssl.CERT_NONE
    connection=HTTPSConnection("192.168.1.1",8001,timeout=10,context=context)
    try:
        connection.connect()
        actual=hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest()
        if not secrets.compare_digest(actual,os.environ["PRIMORDIA_ROUTER_CERT_SHA256"]):
            raise ValueError("Router certificate pin mismatch")
        connection.request("GET",path,headers={"Cookie":"id="+sid} if sid else {})
        response=connection.getresponse();body=response.read(8*1024*1024+1)
        if response.status!=200 or len(body)>8*1024*1024:raise ValueError("Invalid or oversized UI source")
        return body.decode("utf-8",errors="replace")
    finally:connection.close()

def main():
    paths=sys.argv[1:] or os.environ.get("PRIMORDIA_UI_PATHS","/webman/index.cgi").split()
    from synology_ipv6 import Router
    router=Router("192.168.1.1",os.environ["PRIMORDIA_ROUTER_CERT_SHA256"])
    if os.environ.get("PRIMORDIA_ROUTER_USERNAME"):
        router.discover();router.login(os.environ["PRIMORDIA_ROUTER_USERNAME"],os.environ["PRIMORDIA_ROUTER_PASSWORD"])
    try:
        inspect(paths,router.sid,router.synotoken)
    finally:router.logout()

def inspect(paths,sid,synotoken=""):
    for path in paths[:4]:
        try:
            source=fetch(path,sid)
            for private in [sid,synotoken,os.environ.get("PRIMORDIA_ROUTER_USERNAME",""),os.environ.get("PRIMORDIA_ROUTER_PASSWORD","")]:
                if private:source=source.replace(private,"[redacted]")
            # Only static references and bounded vendor request definitions are shown.
            refs=sorted(set(re.findall(r"(?:src|href)=[\"']([^\"']+)",source)))
            matches=[]
            for pattern in [r"SYNO\.Core\.Network\.IPv6",r"SYNO\.Core\.Security\.Firewall",r"jsBaseURL|JSConfig|SynoToken|synotoken|/webman/modules/",r"SYNO\.Core\.Network\.LocalNetwork|dhcpv6|ipv6_enable|loadRulesFromRemote|FwLoadApiMaxVer"]:
                for match in list(re.finditer(pattern,source))[:12]:
                    matches.append(source[max(0,match.start()-120):match.end()+400])
            print(json.dumps({"path":path,"bytes":len(source),"static_references":refs[:80],"style_modules":sorted(set(re.findall(r"@import url\(\"([^\"]+)",source)))[:100],"request_definitions":matches}))
        except (OSError,ValueError) as error:print(json.dumps({"path":path,"error":type(error).__name__}))
if __name__=="__main__":main()

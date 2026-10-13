#!/usr/bin/env python3
"""Actual TLS fixtures prove pin verification precedes router credential sending."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import json
from pathlib import Path
import ssl
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from lan_tls import provision
from synology_ipv6 import Router, RouterError, summarize

class RouterFixture(unittest.TestCase):
    def test_pinned_readonly_session_and_redaction(self):
        with tempfile.TemporaryDirectory(prefix="primordia-router-fixture-") as scratch:
            directory=Path(scratch)
            context=provision(directory,["127.0.0.1","::1"])
            leaf=ssl.PEM_cert_to_DER_cert((directory/"current/server.pem").read_text())
            pin=hashlib.sha256(leaf).hexdigest()
            requests=[]
            class Handler(BaseHTTPRequestHandler):
                def log_message(self,*args):pass
                def handle(self):
                    try:super().handle()
                    except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass
                def do_GET(self):raise AssertionError("Router credentials must not appear in GET URLs")
                def do_POST(self):
                    fields={k:v[0] for k,v in parse_qs(self.rfile.read(int(self.headers['Content-Length'])).decode()).items()}
                    requests.append((self.path,fields))
                    api=fields['api'];method=fields['method']
                    if api=='SYNO.API.Info':
                        data={name:{'path':'auth.cgi' if name=='SYNO.API.Auth' else 'entry.cgi','minVersion':1,'maxVersion':3} for name in fields['query'].split(',')}
                    elif api=='SYNO.API.Auth' and method=='login':
                        if fields.get('account')!='fixture-owner' or fields.get('passwd')!='fixture-password':raise AssertionError('Unexpected fixture login')
                        data={'sid':'private-fixture-session','synotoken':'private-fixture-csrf'}
                    elif api=='SYNO.API.Auth' and method=='logout':data={}
                    else:
                        if method not in {'get','info','list'} or fields.get('_sid')!='private-fixture-session':raise AssertionError('Non-read router operation')
                        data={'model':'RT6600ax','enabled':False,'password':'must-never-be-printed','ssid':'must-never-be-printed'}
                    body=json.dumps({'success':True,'data':data}).encode()
                    self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
            server.socket=context.wrap_socket(server.socket,server_side=True)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            original=http.client.HTTPSConnection
            def connection(host,port,**options):
                self.assertEqual((host,port),('192.168.1.1',8001))
                return original('127.0.0.1',server.server_port,**options)
            try:
                with patch('synology_ipv6.HTTPSConnection',connection):
                    wrong=Router('192.168.1.1','0'*64)
                    wrong.apis={'SYNO.API.Auth':{'path':'auth.cgi','maxVersion':3}}
                    with self.assertRaisesRegex(RouterError,'no credentials sent'):
                        wrong.login('fixture-owner','fixture-password')
                    self.assertEqual(requests,[])
                    router=Router('192.168.1.1',pin);router.discover();router.login('fixture-owner','fixture-password')
                    with self.assertRaisesRegex(RouterError,'read-only allowlist'):
                        router.read('SYNO.Core.Network.Wifi.Hotspot')
                    value=router.read('SYNO.Core.System');router.read('SYNO.Core.Network.IPv6',interface='wan')
                    with self.assertRaisesRegex(RouterError,'Interface is outside'):
                        router.read('SYNO.Core.Network.IPv6',interface='unrelated')
                    router.logout()
                    self.assertEqual(summarize(value),{'model':'RT6600ax','enabled':False})
                    self.assertNotIn('must-never-be-printed',json.dumps(summarize(value)))
                    self.assertNotIn('private-fixture-session',json.dumps(summarize(value)))
                    self.assertEqual([x[1]['method'] for x in requests],['query','login','info','get','logout'])
                    self.assertTrue(all('passwd' not in path and '_sid' not in path for path,_ in requests))
                    self.assertEqual(router.sid,'')
                    with self.assertRaisesRegex(RouterError,'Invalid API path'):
                        router.call('../auth.cgi',{'api':'SYNO.API.Auth','method':'login'})
            finally:server.shutdown();server.server_close();thread.join(timeout=5)

if __name__=='__main__':unittest.main()

#!/usr/bin/env python3
import copy,json,sys,tempfile,threading,socket,unittest,subprocess,shutil,os
from pathlib import Path
from urllib.request import build_opener,ProxyHandler,Request
from urllib.error import HTTPError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from experimental_routing import experimental_route,with_experimental,scope,caddyfile
from experimental_instance import isolated_root,unit_text
from web_gateway import create

class ExperimentalTests(unittest.TestCase):
    def test_only_experimental_routes_are_added_and_existing_routes_are_unchanged(self):
        stable=[{"handle":[{"handler":"static_response","status_code":404}],"match":[{"path":["/metrics"]}]},
                {"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:8766"}],"transport":{"protocol":"http","tls":{"server_name":"localhost"}}}]}]
        original=copy.deepcopy(stable)
        planned,changed=with_experimental(stable)
        self.assertTrue(changed);self.assertEqual(stable,original);self.assertEqual(planned[1:],original)
        again,changed=with_experimental(planned);self.assertFalse(changed);self.assertEqual(again,planned)
        conflict=[{"match":[{"path":["/experimental/*"]}],"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:9999"}]}]}]
        with self.assertRaises(RuntimeError):with_experimental(conflict+stable)
        config={"apps":{"http":{"servers":{"owned":{"listen":["[2001:db8::1]:8766"],"routes":[{"handle":[{"handler":"subroute","routes":stable}]}]},"other":{"listen":[":9988"],"routes":[]}}}}}
        path,value=scope(config);self.assertEqual(value,stable);self.assertEqual(path[-1],"routes")
    def test_caddyfile_insertion_preserves_nested_stable_proxy(self):
        text='{\n admin localhost:2019\n}\nhttps://[2001:db8::1]:8766 {\n header X-Test "{placeholder}"\n reverse_proxy https://127.0.0.1:8766 {\n header_up Host {http.request.hostport}\n }\n}\n'
        edited=caddyfile(text)
        self.assertIn('reverse_proxy https://127.0.0.1:8766 {',edited)
        self.assertEqual(edited.count('handle_path /experimental/*'),1)
        self.assertEqual(caddyfile(edited),edited)
        with self.assertRaises(RuntimeError):caddyfile('https://example.org { reverse_proxy localhost:8766 }\n')
    def test_deployment_root_and_unit_cannot_target_stable(self):
        stable=Path.home()/".local/share/primordia-deploy"
        for root in [stable,stable/"experimental",stable.parent]:
            with self.assertRaises(ValueError):isolated_root(root,stable)
        text=unit_text(Path("/experiment/current"),Path("/experiment/godot"),Path("/experiment/state"),Path("/experiment/credentials"),Path("/experiment/keys"),"abc")
        self.assertIn('--port 8768 --world-port 8769 --proxy-loopback',text)
        self.assertNotIn('primordia.service',text);self.assertNotIn('8766',text)
    @unittest.skipUnless(shutil.which("systemd-analyze"),"systemd unit validator unavailable")
    def test_actual_systemd_parser_accepts_the_candidate_unit(self):
        with tempfile.TemporaryDirectory(prefix="primordia-experimental-unit-") as directory:
            root=Path(directory);current=root/"current";current.mkdir()
            credential=root/"credentials.env";credential.write_text("PRIMORDIA_INVITE=fixture")
            unit=root/"primordia-experimental.service"
            unit.write_text(unit_text(current,Path(sys.executable),root/"state",credential,root/"keys","abc"))
            result=subprocess.run(["systemd-analyze","--user","verify",str(unit)],capture_output=True,text=True,
                env={**os.environ,"XDG_RUNTIME_DIR":f"/run/user/{os.getuid()}"})
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_proxy_origin_checks_keep_foreign_sites_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/"index.html").write_text("experimental")
            with self.assertRaises(ValueError):create(root,root,0,0,bind="0.0.0.0",trusted_proxy=True)
            upstream=socket.socket();upstream.bind(("127.0.0.1",0));upstream.listen()
            def echo_upgrade():
                connection,_=upstream.accept()
                with connection:
                    request=b""
                    while not request.endswith(b"\r\n\r\n"):request+=connection.recv(1)
                    connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n")
            world=threading.Thread(target=echo_upgrade,daemon=True);world.start()
            gateway=create(root,root,0,upstream.getsockname()[1],bind="127.0.0.1",trusted_proxy=True)
            threading.Thread(target=gateway.serve_forever,daemon=True).start()
            port=gateway.server_port
            try:
                opener=build_opener(ProxyHandler({}))
                request=Request(f"http://127.0.0.1:{port}/ws",headers={"Upgrade":"websocket","Origin":"https://foreign.example","X-Forwarded-Proto":"https"})
                with self.assertRaises(HTTPError) as error:opener.open(request,timeout=3)
                self.assertEqual(error.exception.code,403);error.exception.close()
                gateway.trusted_proxy=False
                spoof=Request(f"http://127.0.0.1:{port}/ws",headers={"Upgrade":"websocket","Origin":f"https://127.0.0.1:{port}","X-Forwarded-Proto":"https"})
                with self.assertRaises(HTTPError) as error:opener.open(spoof,timeout=3)
                self.assertEqual(error.exception.code,403);error.exception.close()
                gateway.trusted_proxy=True
                with socket.create_connection(("127.0.0.1",port),timeout=3) as client:
                    client.sendall(f"GET /ws HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nOrigin: https://127.0.0.1:{port}\r\nX-Forwarded-Proto: https\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".encode())
                    self.assertIn(b"101 Switching Protocols",client.recv(4096))
                world.join(3);self.assertFalse(world.is_alive())
            finally:gateway.shutdown();gateway.server_close();upstream.close()
if __name__=="__main__":unittest.main()

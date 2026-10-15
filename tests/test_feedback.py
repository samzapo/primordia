import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    value = importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
publisher = module("durable_feedback")
exporter = module("export_feedback")

class FeedbackTests(unittest.TestCase):
    def test_private_atomic_publication_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);final=root/("a"*32+".json");temporary=root/(final.name+".tmp")
            temporary.write_text('{"report":"original"}')
            publisher.publish(temporary,final)
            self.assertEqual(stat.S_IMODE(final.stat().st_mode),0o600)
            self.assertFalse(temporary.exists())
            temporary.write_text('{"report":"different"}')
            with self.assertRaises(FileExistsError):publisher.publish(temporary,final)
            self.assertEqual(json.loads(final.read_text())["report"],"original")
            with self.assertRaises(ValueError):publisher.publish(temporary,root/"access-keys.json")
    def test_export_is_private_read_only_and_paginated(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);files={}
            for i in range(55):
                record={"version":1,"id":f"{i:032x}","created_unix":i,"author":"private-account-fingerprint","content":{"category":"bug" if i%2 else "feature","title":"Feedback","description":"Keyboard café 🦠"},"context":{"tick":7}}
                path=root/(record["id"]+".json");path.write_text(json.dumps(record));files[path]=path.read_bytes()
            (root/"access-keys.json").write_text('{"never":"export"}')
            (root/("f"*32+".json")).symlink_to(root/"access-keys.json")
            first=exporter.export(root)
            self.assertEqual(first["total_reports"],55)
            self.assertEqual(first["exported"],50)
            self.assertTrue(first["more"])
            self.assertNotIn("private-account-fingerprint",json.dumps(first))
            second=exporter.export(root,first["next_cursor"])
            self.assertEqual(second["exported"],5)
            self.assertFalse(second["more"])
            self.assertEqual(len({r["id"] for r in first["reports"]+second["reports"]}),55)
            self.assertTrue(all(path.read_bytes()==value for path,value in files.items()))
            self.assertEqual(exporter.export(root/"missing")["exported"],0)
            with self.assertRaises(ValueError):exporter.export(root,"invalid-cursor")
    def test_export_size_is_bounded_without_deleting_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for i in range(50):
                record={"version":1,"id":f"{i:032x}","created_unix":i,"author":"private","content":{"description":"🦠"*6000},"context":{}}
                (root/(record["id"]+".json")).write_text(json.dumps(record,ensure_ascii=False))
            page=exporter.export(root)
            self.assertTrue(page["more"])
            self.assertGreater(page["exported"],0)
            self.assertLess(len(json.dumps(page["reports"],ensure_ascii=False).encode()),500001)
            self.assertEqual(len(list(root.glob("*.json"))),50)

if __name__ == "__main__":unittest.main()

import pathlib
import sys
import tempfile
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
from authority_affinity import choose, parse_cpus

class Affinity(unittest.TestCase):
    def fixture(self, root, memory=1024):
        device = root / "bus/pci/devices/0000:41:00.0"
        device.mkdir(parents=True)
        (device / "numa_node").write_text("2")
        node = root / "devices/system/node/node2"
        node.mkdir(parents=True)
        (node / "meminfo").write_text(f"Node 2 MemTotal: {memory} kB")
        (node / "cpulist").write_text("8-15,40-47")
    def test_ranges(self):
        self.assertEqual(parse_cpus("0-2,8,10-11"), {0,1,2,8,10,11})
    def test_gpu_local_memory_and_existing_affinity(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);self.fixture(root)
            self.assertEqual(choose(root,"00000000:41:00.0",{0,8,9,40,63}),{8,9,40})
    def test_memoryless_or_ineligible_node_does_not_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);self.fixture(root,0)
            self.assertIsNone(choose(root,"00000000:41:00.0",set(range(64))))
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);self.fixture(root)
            self.assertIsNone(choose(root,"00000000:41:00.0",{0,1}))
    def test_missing_topology_falls_back_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            self.assertIsNone(choose(root,"00000000:41:00.0",{0,1}))
            self.assertEqual(list(root.iterdir()),[])
if __name__=="__main__":unittest.main()

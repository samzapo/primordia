"""Capture published stable checkpoints without locking or stopping its authority."""
import hashlib
import os
from pathlib import Path
import stat
import tempfile

SLOTS = ("world-0.pworld", "world-1.pworld")
MAX_BYTES = 268435456

def capture(stable_state, experimental_root):
    stable_state, experimental_root = Path(stable_state), Path(experimental_root)
    if stable_state.is_symlink() or experimental_root.is_symlink():
        raise ValueError("Pond storage cannot be a symlink")
    stable_state, experimental_root = stable_state.resolve(), experimental_root.resolve()
    if stable_state == experimental_root or stable_state.is_relative_to(experimental_root) or experimental_root.is_relative_to(stable_state):
        raise ValueError("Snapshot source and destination must be independent")
    target = Path(tempfile.mkdtemp(prefix="stable-pond-snapshot-", dir=experimental_root))
    manifest = {}
    for name in SLOTS:
        source = stable_state / name
        try:
            # Published slots are replaced by rename, never written in place.
            # This descriptor retains one complete inode even if main publishes.
            descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        except FileNotFoundError:
            continue
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
                raise RuntimeError("Invalid stable checkpoint file")
            raw = stream.read(MAX_BYTES + 1)
        digest, separator, payload = raw.partition(b"\n")
        if len(raw) > MAX_BYTES or not separator or digest != hashlib.sha256(payload).hexdigest().encode():
            continue
        destination = target / name
        with destination.open("xb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        destination.chmod(0o600)
        manifest[name] = hashlib.sha256(raw).hexdigest()
    if not manifest:
        raise RuntimeError("No valid published stable checkpoint; refusing to seed experimental")
    for directory in (target, experimental_root):
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    return target, manifest

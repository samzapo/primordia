#!/usr/bin/env python3
"""Verify the reproducible music artifact shipped by every browser deployment."""
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

def check(directory: Path) -> dict:
    manifest = json.loads((directory / "music-bank.json").read_text())
    name = manifest["file"]
    if not re.fullmatch(r"music-bank-[a-f0-9]{24}\.bin", name):
        raise ValueError("Invalid music artifact name")
    data = (directory / name).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != manifest["sha256"] or len(data) != manifest["bytes"] or digest[:24] not in name:
        raise ValueError("Music artifact checksum or length mismatch")
    rate = manifest["rate"]
    notes = manifest["base_notes"]
    if not isinstance(rate, int) or not 8000 <= rate <= 96000 or len(notes) != 17 or not all(isinstance(note, int) and 0 <= note <= 127 for note in notes):
        raise ValueError("Invalid music manifest")
    if struct.unpack_from("<4I", data) != (0x50534d50, 1, rate, 17):
        raise ValueError("Unsupported music artifact header")
    offset = 84
    rms = []
    for count in struct.unpack_from("<17I", data, 16):
        if not 2 <= count <= 3 * rate or offset + count * 4 > len(data):
            raise ValueError("Invalid music sample extent")
        samples = [value[0] for value in struct.iter_unpack("<f", data[offset:offset + count * 4])]
        if not all(math.isfinite(value) and abs(value) <= 2 for value in samples):
            raise ValueError("Invalid synthesized sample")
        rms.append(math.sqrt(sum(value * value for value in samples) / count))
        offset += count * 4
    if offset != len(data) or min(rms) <= .0001:
        raise ValueError("Truncated or silent music bank")
    return {"file": name, "instruments": 17, "bytes": len(data), "rms_min": min(rms), "rms_max": max(rms)}

if __name__ == "__main__":
    print("WEB_MUSIC_ARTIFACT " + json.dumps(check(Path(sys.argv[1]))))

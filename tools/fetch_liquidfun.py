#!/usr/bin/env python3
"""Fetch only the pinned original LiquidFun library into ignored build/."""
import hashlib
import io
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request

PIN = "7f20402173fd143a3988c921bc384459c6a858f2"
SHA256 = "40e6233b644f8c8ce23b92033546bed45a446b17f892c9170ffe8c9c205fab7f"
ROOT = Path(__file__).resolve().parent.parent / "build" / "liquidfun-original"

def main():
    marker = ROOT / ".pin"
    if marker.exists() and marker.read_text().strip() == PIN:
        return
    url = f"https://codeload.github.com/google/liquidfun/tar.gz/{PIN}"
    with urllib.request.urlopen(url, timeout=60) as response:
        archive = response.read(40 * 1024 * 1024 + 1)
    if hashlib.sha256(archive).hexdigest() != SHA256:
        raise RuntimeError("Original LiquidFun archive checksum mismatch")
    ROOT.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
        for item in source:
            parts = PurePosixPath(item.name).parts
            if len(parts) < 2:
                continue
            relative = PurePosixPath(*parts[1:])
            if not (str(relative).startswith("liquidfun/Box2D/Box2D/") or
                    str(relative) in ("liquidfun/Box2D/License.txt", "liquidfun/Box2D/Readme.txt")):
                continue
            if ".." in relative.parts or item.issym() or item.islnk():
                raise RuntimeError("Unsafe LiquidFun library archive member")
            target = ROOT.joinpath(*relative.parts)
            if item.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.extractfile(item).read())
    marker.write_text(PIN + "\n")

if __name__ == "__main__":
    main()

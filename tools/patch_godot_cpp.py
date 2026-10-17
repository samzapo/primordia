#!/usr/bin/env python3
"""Apply the pinned Dictionary lifetime backport before bindings are generated."""
import argparse
import hashlib
from pathlib import Path
import subprocess

REVISION = "714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa"
SOURCE_SHA256 = "b6e4422937512222b0f86abd254719b25bc507e142636816c99058b7a6a9d89e"
OLD = """    # Move assignment.
    result.append(f"{class_name} &{class_name}::operator=({class_name} &&p_other) {{")
    if needs_copy_instead_of_move(class_name) and copy_constructor_index >= 0:
        result.append(
            f"\\tinternal::_call_builtin_constructor(_method_bindings.constructor_{copy_constructor_index}, &opaque, &p_other);"
        )
    else:
        result.append("\\tstd::swap(opaque, p_other.opaque);")
    result.append("\\treturn *this;")
"""
NEW = """    # Move assignment. Both initialized owners must remain destructible.
    # Backport the ownership swap used by newer godot-cpp generators.
    result.append(f"{class_name} &{class_name}::operator=({class_name} &&p_other) {{")
    result.append("\\tstd::swap(opaque, p_other.opaque);")
    result.append("\\treturn *this;")
"""

def patched(source: bytes) -> bytes:
    replacement = source.replace(OLD.encode(), NEW.encode())
    if replacement == source or source.count(OLD.encode()) != 1:
        raise ValueError("Pinned Dictionary move-assignment template changed")
    return replacement

def apply(directory: Path) -> bool:
    revision = subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        raise ValueError("Unexpected godot-cpp revision")
    original = subprocess.check_output(["git", "-C", str(directory), "show", "HEAD:binding_generator.py"])
    if hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise ValueError("Unexpected pinned generator contents")
    target = directory / "binding_generator.py"
    desired = patched(original)
    current = target.read_bytes()
    if current == desired:
        return False
    if current != original:
        raise ValueError("Refusing to overwrite unrelated binding-generator edits")
    temporary = target.with_name(target.name + ".primordia.tmp")
    temporary.write_bytes(desired)
    temporary.replace(target)
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print("Native Dictionary lifetime patch:", "applied" if apply(parser.parse_args().directory) else "already present")

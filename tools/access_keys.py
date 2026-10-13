#!/usr/bin/env python3
"""Create owner-requested access keys outside source; stdout contains only hashes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets


def generate(count, output):
    if not 1 <= count <= 100:raise ValueError("Request between one and100 keys")
    output=Path(output).expanduser().resolve()
    source=Path(__file__).resolve().parents[1]
    if output==source or source in output.parents:raise ValueError("Store live access keys outside the repository")
    output.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    keys=["pmd_"+secrets.token_urlsafe(32) for _ in range(count)]
    descriptor=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w') as file:
        file.write("Primordia personal access keys — keep private and give one key to each player.\n\n")
        for index,key in enumerate(keys,1):file.write(str(index)+". "+key+"\n")
        file.flush();os.fsync(file.fileno())
    return {"hashes":[hashlib.sha256(key.encode()).hexdigest() for key in keys]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--count',type=int,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(generate(args.count,args.output)))

if __name__=='__main__':main()

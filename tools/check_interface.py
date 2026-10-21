#!/usr/bin/env python3
"""Small desktop/touch contract before either pond release; never a speed test."""
import argparse,os,re,subprocess,tempfile
from pathlib import Path

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument("--godot",required=True)
 args=parser.parse_args()
 project=Path(__file__).resolve().parents[1]
 with tempfile.TemporaryDirectory(prefix="primordia-interface-") as fixture:
  environment={**os.environ,"PRIMORDIA_BACKEND":"script","XDG_DATA_HOME":fixture}
  result=subprocess.run([args.godot,"--headless","--path",str(project),"--script","res://tests/interface_run.gd"],capture_output=True,text=True,timeout=60,env=environment)
 output=result.stdout+result.stderr
 print(output,end="")
 if result.returncode or re.search(r"SCRIPT ERROR:|SHADER ERROR:|Parse Error:|Compile Error:|^ERROR:",output,re.M) or not re.search(r"SHARED INTERFACE: [0-9]+ assertions, 0 failures",output):
  raise SystemExit("Desktop/touch interface contract failed; release was not started")
if __name__=="__main__":main()

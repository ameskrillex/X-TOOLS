"""Build the x86 bridge with a caller-supplied Zig 0.13.0 executable."""
from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('--zig',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/cef-native';out.mkdir(parents=True,exist_ok=True)
common=[str(Path(a.zig).resolve()),'c++','-target','x86-windows-gnu','-std=c++17','-O2','-static','-s']
subprocess.run(common+['-shared',str(root/'native/cef_bridge/bridge.cpp'),'-lws2_32','-o',str(out/'XToolsBridge.asi')],check=True)
subprocess.run(common+[str(root/'native/cef_bridge/host.cpp'),'-o',str(out/'bridge-host.exe')],check=True)
print(out)

import sys
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load
b, slices = load("build/qmvcam-arm64.dylib")
sl = slices[0]
syms = sl.symbols()
und = sorted({n for n,t,sec,v in syms if not (t & 1)})
print("undefined symbols:", len(und))
for n in und: print("  ", n)

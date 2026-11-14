import sys
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load
b, slices = load("build/qmvcam-arm64.dylib")
sl = slices[0]
und_sect = []; und_weak = []
for n,t,sec,v in sl.symbols():
    kind = t & 0x0e
    if kind == 0x0 and v == 0:      # N_UNDF
        und_sect.append((n, bool(t & 0x01)))
print("真·未定义符号:", len(und_sect))
for n, ext in sorted(und_sect):
    print("  ", n, "(ext)" if ext else "(local)")
print("--- 含 MSHook 的 ---")
print([n for n,_ in und_sect if "MSHook" in n] or "无")

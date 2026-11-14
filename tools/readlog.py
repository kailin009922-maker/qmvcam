import sys, re, os
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\dev_sys3.log"
if not os.path.exists(p):
    print("no log file yet"); sys.exit()
lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
print("total lines", len(lines))
pats = ["vcam", "vcameracrack", "qmvcam", "ElleKit", "ellekit", "injector", "dyld", "dlopen", "code signature", "MSHook"]
hits = [l for l in lines if any(k.lower() in l.lower() for k in pats)]
print("hits", len(hits))
for l in hits[-80:]:
    print(l[:240])

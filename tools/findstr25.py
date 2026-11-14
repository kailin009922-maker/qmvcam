b=open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","rb").read()
for pat in (b"HHVCAM888", b"TG@", b"taokk", b"qianmian"):
    i=b.find(pat)
    print(pat, "at", i)
# 打印几个候选可打印串
import re
cands = re.findall(rb"[ -~]{6,40}", b)
seen=set()
for c in cands:
    s=c.decode()
    if any(k in s for k in ("HHV","TG@","taokk","qianmian","VCAM","vcam")) and s not in seen:
        seen.add(s); print(" ", s)
    if len(seen)>10: break

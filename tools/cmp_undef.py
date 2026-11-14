import sys
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load

def und(p):
    b, slices = load(p)
    sl = slices[0]
    out = set()
    for n,t,sec,v in sl.symbols():
        if (t & 0x0e) == 0 and v == 0:
            out.add(n)
    return out

a = und(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")
c = und(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")
print("98d undefined:", len(a), " 25r20:", len(c))
only98 = sorted(a - c)
only25 = sorted(c - a)
print("98d only (%d):" % len(only98))
for s in only98: print("   ", s)
print("25r20 only (%d):" % len(only25))
for s in only25[:20]: print("   ", s)

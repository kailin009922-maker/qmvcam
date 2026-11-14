import sys
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load
def libs(p):
    b, s = load(p)
    return [x[1] for x in s[0].libs]
a = libs(r"qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")
b = libs(r"qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")
print("98d only:", [x for x in a if x not in b])
print("25r20 only:", [x for x in b if x not in a])
print("98d count", len(a), "25r20 count", len(b))

import sys, struct
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load
for tag, p in (
  ("98d", r"qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"),
  ("25r20", r"qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"),
):
    b, slices = load(p)
    print("==", tag, len(b), "slices", len(slices))
    for i, sl in enumerate(slices):
        print(f"  slice{i} cpu={sl.cpu} sub={sl.sub} minos/sdk={sl.build}")
        print("    rpaths:", sl.rpaths)
        print("    libs:", [s for k,s,c in sl.libs if 'Substrate' in s or 'substrate' in s])
        print("    flags:", hex(sl.flags))

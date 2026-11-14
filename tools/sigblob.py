import sys, struct
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm")
from machlib import load
def sigblobs(p):
    b, slices = load(p)
    out = {}
    for i, sl in enumerate(slices):
        data = b[sl.off: sl.off+sl.size]
        # find LC_CODE_SIGNATURE
        cs = sl.code_signature
        if not cs: out[i]=None; continue
        off, size = cs
        blob = data[off:off+size]
        magic, length, count = struct.unpack(">III", blob[:12])
        parts = []
        for k in range(count):
            typ, boff = struct.unpack(">II", blob[12+8*k: 20+8*k])
            blen = struct.unpack(">I", blob[boff:boff+4])[0]
            parts.append((hex(typ), blen))
        out[i] = (hex(magic), size, parts)
    return out
for tag,p in (("98d", r"qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"),
              ("25r20", r"qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")):
    print("==", tag)
    for i,v in sigblobs(p).items():
        print("  slice",i,v)

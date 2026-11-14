import struct, sys, re
def blobs(path):
    b = open(path,'rb').read()
    res = []
    for m in re.finditer(b'\xfa\xde\x0c\xc0', b):
        off = m.start()
        try:
            magic, length, count = struct.unpack('>III', b[off:off+12])
        except Exception: continue
        if length < 12 or length > 0x400000: continue
        items = []
        for k in range(min(count, 20)):
            typ, boff = struct.unpack('>II', b[off+12+8*k: off+20+8*k])
            if boff+4 > length: break
            blen = struct.unpack('>I', b[off+boff: off+boff+4])[0]
            items.append((typ, blen, off+boff))
        res.append((off, length, items))
    return res, b
for tag, p in (("98d", r"qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"),
               ("25r20", r"qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib")):
    print("=====", tag)
    res, b = blobs(p)
    for off, length, items in res[:2]:
        print(" superblob @%d len=%d" % (off, length))
        for typ, blen, boff in items:
            name = {1:'CodeDirectory',2:'Requirements',5:'Entitlements',0x10000:'CMS'}.get(typ, hex(typ))
            extra = ""
            if typ == 5:
                xml = b[boff+8: boff+blen]
                extra = " | " + xml.decode('utf-8','replace')[:400].replace('\n',' ')
            print("   ", name, blen, extra)

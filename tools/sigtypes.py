import struct
def parse(path, label):
    b = open(path,'rb').read()
    # 找 CodeDirectory magic 0xfade0c02，然后向前找 SuperBlob 0xfade0cc0
    print("=====", label)
    idx = 0
    found = 0
    while True:
        i = b.find(b'\xfa\xde\x0c\xc0', idx)
        if i < 0: break
        idx = i + 4
        magic, length, count = struct.unpack('>III', b[i:i+12])
        if length <= 12 or length > 0x800000: continue
        print("  superblob @%d len=%d count=%d" % (i, length, count))
        for k in range(count):
            typ, off = struct.unpack('>II', b[i+12+8*k: i+20+8*k])
            if off+8 > length: continue
            blen = struct.unpack('>I', b[i+off+4: i+off+8])[0]
            name = {0:'CodeDirectory',2:'Requirements',5:'Entitlements',0x10000:'CMS',1:'Info',3:'ResourceDir',4:'Application',6:'DMG',7:'Ticket'}.get(typ, hex(typ))
            print("     %-14s len=%d" % (name, blen))
        found += 1
        if found >= 2: break

parse(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib", "vendor 25r20")
parse(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64.dylib", "mine 3.4.0")

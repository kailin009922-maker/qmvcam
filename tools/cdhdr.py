import struct
def cd(p,label):
    b=open(p,'rb').read()
    base = struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
    i=b.find(struct.pack('>I',0xfade0c02), base)
    ver, flags = struct.unpack('>II', b[i+8:i+16])
    hashOff, identOff, nSpecial, nCode, codeLimit = struct.unpack('>5I', b[i+16:i+36])
    hashSize, hashType, platform, pageSize = b[i+36], b[i+37], b[i+38], b[i+39]
    print("==",label)
    print("   version=0x%x flags=0x%x hashType=%d platform=%d pageSize=%d(n=%d) nCode=%d codeLimit=%d hashSize=%d"
          % (ver, flags, hashType, platform, pageSize, 1<<pageSize if pageSize else 0, nCode, codeLimit, hashSize))
    # 若有 execSeg 字段（version>=0x20300）
    if ver >= 0x20300:
        off = i+40
        execSegBase, execSegLimit, execSegFlags = struct.unpack('>QQQ', b[off:off+24])
        print("   execSegBase=%d execSegLimit=%d execSegFlags=0x%x" % (execSegBase, execSegLimit, execSegFlags))
cd(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d")
cd(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")
cd(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64e.dylib","mine arm64e")

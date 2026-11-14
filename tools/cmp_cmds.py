import struct
NAMES = {
 0x1:'LC_SEGMENT',0x2:'LC_SYMTAB',0xb:'LC_DYSYMTAB',0xc:'LC_LOAD_DYLIB',0xd:'LC_ID_DYLIB',
 0xe:'LC_LOAD_DYLINKER',0x19:'LC_SEGMENT_64',0x1b:'LC_UUID',0x1d:'LC_CODE_SIGNATURE',
 0x22:'LC_DYLD_INFO',0x80000022:'LC_DYLD_INFO_ONLY',0x24:'LC_VERSION_MIN_IPHONEOS',
 0x26:'LC_FUNCTION_STARTS',0x29:'LC_DATA_IN_CODE',0x2b:'LC_SOURCE_VERSION',0x2c:'LC_DYLIB_CODE_SIGN_DRS',
 0x32:'LC_BUILD_VERSION',0x33:'LC_DYLD_EXPORTS_TRIE',0x80000034:'LC_DYLD_CHAINED_FIXUPS',
 0x1c:'LC_ENCRYPTION_INFO',0x2a:'LC_ENCRYPTION_INFO_64',0x1e:'LC_SEGMENT_SPLIT_INFO',
 0x8000001c:'LC_RPATH',0x1f:'LC_LAZY_LOAD_DYLIB',0x8000001f:'LC_LOAD_WEAK_DYLIB',
 0x80000023:'LC_LOAD_UPWARD_DYLIB',
}
def dump(p, label):
    b=open(p,'rb').read()
    magic=struct.unpack('>I',b[:4])[0]
    if magic==0xcafebabe:
        off=struct.unpack('>I',b[16:20])[0]
    else:
        off=0
    ncmds=struct.unpack('<I',b[off+16:off+20])[0]
    p2=off+32; out=[]
    for _ in range(ncmds):
        cmd,sz=struct.unpack('<II',b[p2:p2+8])
        out.append(NAMES.get(cmd, hex(cmd)))
        p2+=sz
    print("==",label,"ncmds",ncmds)
    print("  ", ", ".join(sorted(set(out))))
    return set(out)
a=dump(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d")
c=dump(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")
print("98d only:", a-c)
print("25r20 only:", c-a)

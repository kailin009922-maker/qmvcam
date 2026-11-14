import struct
def enc(p,label):
    b=open(p,'rb').read()
    off=struct.unpack('>I',b[16:20])[0] if struct.unpack('>I',b[:4])[0]==0xcafebabe else 0
    ncmds=struct.unpack('<I',b[off+16:off+20])[0]; q=off+32
    for _ in range(ncmds):
        cmd,sz=struct.unpack('<II',b[q:q+8])
        if cmd==0x2a:
            cryptoff,cryptsize,cryptid,pad=struct.unpack('<IIII', b[q+8:q+24])
            print(label,"LC_ENCRYPTION_INFO_64 cryptoff=%d cryptsize=%d cryptid=%d" % (cryptoff,cryptsize,cryptid))
        q+=sz
enc(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d ")
enc(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")

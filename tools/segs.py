import struct
def segs(p,label):
    b=open(p,'rb').read()
    off=struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
    ncmds=struct.unpack('<I', b[off+16:off+20])[0]; q=off+32; out=[]
    for _ in range(ncmds):
        cmd,sz=struct.unpack('<II', b[q:q+8])
        if cmd==0x19:
            name=b[q+8:q+24].split(b'\0')[0].decode('ascii','replace')
            vmaddr,vmsize,fileoff,filesize=struct.unpack('<QQQQ', b[q+24:q+56])
            out.append((name,vmsize,filesize))
        q+=sz
    print("==",label)
    for n,vs,fs in out: print("   %-16s vmsize=%-9d filesize=%d" % (n,vs,fs))
segs(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")
segs(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d")
segs(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64e-f0.dylib","mine")

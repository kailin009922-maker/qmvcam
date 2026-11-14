import struct
FMT={1:"ARM64E",2:"64",3:"32",4:"32_CACHE",5:"32_FIRMWARE",6:"64_OFFSET",7:"ARM64E_KERNEL",
     8:"64_KERNEL_CACHE",9:"ARM64E_USERLAND",10:"ARM64E_FIRMWARE",11:"X86_64_KERNEL_CACHE",12:"ARM64E_USERLAND24"}
def fx(p,label):
    b=open(p,'rb').read()
    off=struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
    ncmds=struct.unpack('<I', b[off+16:off+20])[0]; q=off+32
    for _ in range(ncmds):
        cmd,sz=struct.unpack('<II', b[q:q+8])
        if (cmd & 0x7fffffff)==0x34:
            dataoff,datasize=struct.unpack('<II', b[q+8:q+16])
            base=off+dataoff
            ver,starts,imports,syms,icount,ifmt,symfmt=struct.unpack('<7I', b[base:base+28])
            si=base+starts
            seg_count=struct.unpack('<I', b[si:si+4])[0]
            fmts=[]
            for s in range(seg_count):
                so=struct.unpack('<I', b[si+4+4*s: si+8+4*s])[0]
                if so==0: continue
                sb=si+so
                size,page_size,pointer_format=struct.unpack('<IHH', b[sb:sb+8])
                fmts.append(FMT.get(pointer_format,pointer_format))
            print("== %-12s imports=%d pointer_formats=%s" % (label, icount, fmts))
            return
        q+=sz
    print("== %-12s no chained fixups" % label)
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d")
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64e-f0.dylib","mine arm64e")
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64.dylib","mine arm64")

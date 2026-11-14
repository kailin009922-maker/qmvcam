import struct
def fx(p,label):
    b=open(p,'rb').read()
    off=struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
    ncmds=struct.unpack('<I', b[off+16:off+20])[0]; q=off+32
    for _ in range(ncmds):
        cmd,sz=struct.unpack('<II', b[q:q+8])
        if cmd in (0x80000034,0x34):
            dataoff,datasize=struct.unpack('<II', b[q+8:q+16])
            base=off+dataoff
            ver,starts,imports,syms,icount,ifmt,symfmt=struct.unpack('<7I', b[base:base+28])
            print("==",label,"fixups_version=%d imports_format=%d imports=%d starts=+%d" % (ver,ifmt,icount,starts))
            # 第一个 starts_in_image: seg_count, seg_info_offset[]
            si=base+starts
            seg_count=struct.unpack('<I', b[si:si+4])[0]
            print("   segments=%d" % seg_count)
            for s in range(seg_count):
                so=struct.unpack('<I', b[si+4+4*s: si+8+4*s])[0]
                if so==0: continue
                segbase=si+so
                size,page_start=struct.unpack('<IH', b[segbase:segbase+6])
                fmt=(page_start>>12)&0xF
                print("     seg%d size=%d page_start=0x%x pointer_format=%d" % (s,size,page_start,fmt))
            return
        q+=sz
    print("==",label,"no chained fixups")
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")
fx(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmarch_e.dylib","mine C probe")

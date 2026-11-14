import struct
P = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
b = open(P,'rb').read()
# 取 arm64 slice（offset 32768）
off = 32768
b = b[off:off+921504]
ncmds = struct.unpack('<I', b[16:20])[0]
q = 32
segs=[]; sections=[]
for _ in range(ncmds):
    cmd,sz = struct.unpack('<II', b[q:q+8])
    if cmd==0x19:
        name=b[q+8:q+24].split(b'\0')[0].decode()
        vmaddr,vmsize,fileoff,filesize = struct.unpack('<QQQQ', b[q+24:q+56])
        nsects = struct.unpack('<I', b[q+64:q+68])[0]
        sp=q+72
        for _s in range(nsects):
            sn=b[sp:sp+16].split(b'\0')[0].decode()
            sg=b[sp+16:sp+32].split(b'\0')[0].decode()
            addr,size,offset = struct.unpack('<QQI', b[sp+32:sp+52])
            sections.append((sg,sn,addr,size,offset))
            sp+=80
        segs.append((name,vmaddr,vmsize,fileoff,filesize))
    q+=sz
print("segments:", [(s[0],hex(s[1])) for s in segs])
def sect(n):
    for sg,sn,addr,size,offset in sections:
        if sn==n: return (addr,size,offset)
    return None
for n in ('__cstring','__objc_selrefs','__objc_methname','__text'):
    print(n, sect(n))

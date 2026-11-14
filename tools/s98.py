import struct
from capstone import *
P=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
raw=open(P,'rb').read(); b=raw[16384:16384+1005472]
ncmds=struct.unpack('<I', b[16:20])[0]; q=32; sects={}
for _ in range(ncmds):
    cmd,sz=struct.unpack('<II', b[q:q+8])
    if cmd==0x19:
        nsects=struct.unpack('<I', b[q+64:q+68])[0]; sp=q+72
        for _s in range(nsects):
            sn=b[sp:sp+16].split(b'\0')[0].decode(); sg=b[sp+16:sp+32].split(b'\0')[0].decode()
            addr,size,off=struct.unpack('<QQI', b[sp+32:sp+52]); sects[(sg,sn)]=(addr,size,off); sp+=80
    q+=sz
print({k:(hex(v[0]),v[1]) for k,v in sects.items() if k[1] in ('__cstring','__cfstring','__const','__data','__objc_selrefs')})
cstr=sects[('__TEXT','__cstring')]
def find(s):
    i=b.find(s, cstr[2], cstr[2]+cstr[1])
    return i
for name in (b"Floating window created", b"SpringBoard hooks initialized", b"Loading in process"):
    print(name, "->", hex(find(name)) if find(name)>0 else None)

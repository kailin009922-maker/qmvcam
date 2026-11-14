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
cs=sects[('__TEXT','__cstring')]
targets={}
for name in (b"mediaserverd", b"SpringBoard"):
    i=b.find(name, cs[2], cs[2]+cs[1]); targets[name]=i
print({k.decode():hex(v) for k,v in targets.items() if v>0})
# 扫所有数据段找指向这些地址的 8 字节
def scan_ptr(addr):
    hits=[]
    for (sg,sn),(a,size,off) in sects.items():
        if sg not in ('__DATA_CONST','__DATA'): continue
        for i in range(0,size-8,8):
            w=struct.unpack('<Q', b[off+i:off+i+8])[0]
            if (w & ((1<<36)-1)) == addr:
                hits.append((sg,sn,a+i))
    return hits
for k,v in targets.items():
    if v>0:
        print(k.decode(), "->", [(s,n,hex(x)) for s,n,x in scan_ptr(v)][:6])

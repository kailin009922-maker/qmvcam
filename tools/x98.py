import struct
from capstone import *
P=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
raw=open(P,'rb').read()
b = raw[16384:16384+1005472]
ncmds=struct.unpack('<I', b[16:20])[0]; q=32; sects={}
for _ in range(ncmds):
    cmd,sz=struct.unpack('<II', b[q:q+8])
    if cmd==0x19:
        nsects=struct.unpack('<I', b[q+64:q+68])[0]; sp=q+72
        for _s in range(nsects):
            sn=b[sp:sp+16].split(b'\0')[0].decode(); sg=b[sp+16:sp+32].split(b'\0')[0].decode()
            addr,size,off=struct.unpack('<QQI', b[sp+32:sp+52])
            sects[(sg,sn)]=(addr,size,off); sp+=80
    q+=sz
t=sects[('__TEXT','__text')]
print("__text addr=%d size=%d off=%d" % t)
def addr_of(s):
    i=b.find(s)
    return i+16384 if False else (i if i>0 else None)
tgts={}
for name in [b"Loading in process", b"Floating window created", b"SpringBoard hooks initialized", b"Initializing in mediaserverd"]:
    tgts[name]=b.find(name)
print({k.decode():(hex(v) if v and v>0 else None) for k,v in tgts.items()})
md=Cs(CS_ARCH_ARM64, CS_MODE_ARM); last={}; hits={}
for insn in md.disasm(b[t[2]:t[2]+t[1]], t[0]):
    if insn.mnemonic=='adrp':
        try:
            r,imm=insn.op_str.split(', '); last[r]=int(imm.strip('#'),16)
        except: pass
    elif insn.mnemonic=='add':
        try:
            p=[x.strip() for x in insn.op_str.split(',')]
            if len(p)>=3 and p[1] in last:
                a=last[p[1]]+int(p[2].lstrip('#'),0)
                for k,v in tgts.items():
                    if v>0 and v==a: hits.setdefault(k.decode(),[]).append(insn.address)
        except: pass
for k,v in hits.items(): print(k, [hex(x) for x in v][:6])

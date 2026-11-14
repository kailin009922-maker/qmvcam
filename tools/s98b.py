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
CF=sects[('__DATA_CONST','__cfstring')]; TX=sects[('__TEXT','__text')]
def cf_for(cstr_addr):
    out=[]
    off,size=CF[2],CF[1]
    for i in range(0,size,32):
        w=struct.unpack('<Q', b[off+i+16:off+i+24])[0]
        if (w & ((1<<36)-1)) == cstr_addr:
            out.append(CF[0]+i)
    return out
def xrefs(addrs):
    md=Cs(CS_ARCH_ARM64, CS_MODE_ARM); last={}; hits=[]
    for insn in md.disasm(b[TX[2]:TX[2]+TX[1]], TX[0]):
        if insn.mnemonic=='adrp':
            try:
                r,imm=insn.op_str.split(', '); last[r]=int(imm.strip('#'),16)
            except: pass
        elif insn.mnemonic=='add':
            try:
                p=[x.strip() for x in insn.op_str.split(',')]
                if len(p)>=3 and p[1] in last:
                    a=last[p[1]]+int(p[2].lstrip('#'),0)
                    if a in addrs: hits.append((insn.address,a))
            except: pass
    return hits
for label, ca in (("Floating window created",0xc1765), ("SpringBoard hooks initialized",0xc18ce)):
    cfs=cf_for(ca); print(label, "cfstrings:", [hex(x) for x in cfs])
    hs=xrefs(set(cfs)); print("  xrefs:", [(hex(a),hex(t)) for a,t in hs][:8])

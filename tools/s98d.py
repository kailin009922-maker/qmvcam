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
TX=sects[('__TEXT','__text')]
want={0xda9b0:'mediaserverd',0xda970:'SpringBoard'}
md=Cs(CS_ARCH_ARM64, CS_MODE_ARM); last={}; sites=[]
insns=list(md.disasm(b[TX[2]:TX[2]+TX[1]], TX[0]))
for i,insn in enumerate(insns):
    if insn.mnemonic=='adrp':
        try:
            r,imm=insn.op_str.split(', '); last[r]=int(imm.strip('#'),16)
        except: pass
    elif insn.mnemonic in ('add','ldr'):
        try:
            p=[x.strip() for x in insn.op_str.split(',')]
            base=p[1] if len(p)>1 else ''
            if base in last:
                if insn.mnemonic=='add' and len(p)>=3:
                    a=last[base]+int(p[2].lstrip('#'),0)
                else:
                    continue
                if a in want:
                    sites.append((insn.address, a, i))
        except: pass
for addr,a,i in sites:
    print("== %s @ %s" % (want[a], hex(addr)))
    for j in range(max(0,i-6), min(len(insns), i+22)):
        x=insns[j]
        print("   %s  %-8s %s" % (hex(x.address), x.mnemonic, x.op_str))

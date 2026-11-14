import struct
from capstone import *
P=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
raw=open(P,'rb').read()[:16384+921504]; b=raw[32768:]
METH=(755826,37611); TEXT=(16384,154184)

def addr_of(s):
    off,size=METH; i=b.find(s, off, off+size); return i

needles=[b"emitSampleBuffer:", b"renderSampleBuffer:forInput:", b"Frame queue prefilled", b"Prefilling frame queue"]
addrs={s:addr_of(s) for s in needles}
print({k.decode(): (hex(v) if v>0 else None) for k,v in addrs.items()})

tgt=set(v for v in addrs.values() if v>0)
md=Cs(CS_ARCH_ARM64, CS_MODE_ARM)
toff,tsize=TEXT
last={}
sites={}
for insn in md.disasm(b[toff:toff+tsize], toff):
    if insn.mnemonic=='adrp':
        try:
            r,imm=insn.op_str.split(', '); last[r]=int(imm,16)
        except: pass
    elif insn.mnemonic=='add':
        try:
            p=insn.op_str.split(', ')
            r,base,offv=p[0],p[1],p[2].lstrip('#')
            if base in last and offv.isdigit():
                a=last[base]+int(offv)
                if a in tgt:
                    sites.setdefault(a,[]).append(insn.address)
        except: pass
for a,lst in sites.items():
    name=[k.decode() for k,v in addrs.items() if v==a]
    print(name, "cxrefs:", [hex(x) for x in lst][:8])

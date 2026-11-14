import struct
from capstone import *
P=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
raw=open(P,'rb').read()[:16384+921504]; b=raw[32768:]
TEXT=(16384,154184)
def addr_of(s):
    i=b.find(s)
    return i if 0<i<len(b) else None
needles=[b"emitSampleBuffer:", b"renderSampleBuffer:forInput:", b"Frame queue prefilled with", b"Prefilling frame queue"]
addrs={s:addr_of(s) for s in needles}
print({k.decode(errors='replace'): (hex(v) if v else None) for k,v in addrs.items()})
tgt=set(v for v in addrs.values() if v)
md=Cs(CS_ARCH_ARM64, CS_MODE_ARM)
last={}; sites={}
for insn in md.disasm(b[TEXT[0]:TEXT[0]+TEXT[1]], TEXT[0]):
    if insn.mnemonic=='adrp':
        try:
            r,imm=insn.op_str.split(', '); last[r]=int(imm,16)
        except: pass
    elif insn.mnemonic=='add':
        try:
            p=insn.op_str.split(', ')
            if len(p)>=3:
                r,base,offv=p[0],p[1],p[2].strip().lstrip('#')
                if base in last:
                    a=last[base]+int(offv,0)
                    if a in tgt: sites.setdefault(a,[]).append(insn.address)
        except: pass
for a,lst in sites.items():
    name=[k.decode(errors='replace') for k,v in addrs.items() if v==a]
    print(name, [hex(x) for x in lst][:10])

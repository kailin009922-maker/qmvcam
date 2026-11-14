import struct
from capstone import *
P=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
raw=open(P,'rb').read()[:16384+921504]
b=raw[32768:]
SELREFS=(869896,9904)
METH=(755826,37611)
TEXT=(16384,154184)

def find_str(needle):
    off,size=METH
    i=b.find(needle, off, off+size)
    return i if i>=0 else None

target=find_str(b"emitSampleBuffer:")
print("methname offset:", target, hex(target) if target else None)

# selrefs: 64_OFFSET chained pointers
hits=[]
off,size=SELREFS
for i in range(0,size,8):
    v=struct.unpack('<Q', b[off+i:off+i+8])[0]
    bind = v & 1
    if bind: continue
    tgt = v & ((1<<36)-1)
    if tgt == target:
        hits.append(off+i)
print("selref slots:", [hex(h) for h in hits])

# 扫 __text 找 adrp+add 指向这些 selref
md=Cs(CS_ARCH_ARM64, CS_MODE_ARM)
md.detail=False
toff,tsize=TEXT
code=b[toff:toff+tsize]
last_adrp={}
sites=[]
for insn in md.disasm(code, toff):
    if insn.mnemonic=='adrp':
        try:
            reg, imm = insn.op_str.split(', ')
            last_adrp[reg]=(int(imm,16), insn.address)
        except: pass
    elif insn.mnemonic in ('add','ldr') and last_adrp:
        try:
            reg = insn.op_str.split(', ')[0]
            parts = insn.op_str.split(', ')
            if len(parts)>=3:
                base=parts[1]; offv=parts[2].lstrip('#')
                if base in last_adrp and offv.isdigit():
                    addr=last_adrp[base][0]+int(offv)
                    if addr in hits:
                        sites.append((insn.address, hex(addr)))
        except: pass
print("code sites:", [(hex(a),x) for a,x in sites])

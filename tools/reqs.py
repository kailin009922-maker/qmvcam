import struct
def reqs(p,label):
    b=open(p,'rb').read()
    off = struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
    # 在 slice 内找 superblob
    i = b.find(b'\xfa\xde\x0c\xc0', off)
    if i < 0: print(label,"no superblob"); return
    magic, length, count = struct.unpack('>III', b[i:i+12])
    print("==",label,"superblob len",length,"count",count)
    for k in range(count):
        typ, boff = struct.unpack('>II', b[i+12+8*k: i+20+8*k])
        blen = struct.unpack('>I', b[i+boff+4: i+boff+8])[0]
        blob = b[i+boff: i+boff+blen]
        print("   type=0x%x len=%d" % (typ, blen))
        if typ == 2:
            ascii_part = ''.join(chr(c) if 32 <= c < 127 else '.' for c in blob)
            print("     ", ascii_part[:400])
reqs(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","98d")
reqs(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","25r20")

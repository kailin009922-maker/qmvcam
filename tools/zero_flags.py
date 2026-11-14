import struct, shutil, sys
src = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64e.dylib"
dst = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64e-f0.dylib"
b = bytearray(open(src,'rb').read())
base = struct.unpack('>I', b[16:20])[0] if struct.unpack('>I', b[:4])[0]==0xcafebabe else 0
i = b.find(struct.pack('>I',0xfade0c02), base)
old = struct.unpack('>I', b[i+12:i+16])[0]
struct.pack_into('>I', b, i+12, 0)
print("CD flags 0x%x -> 0x0 at offset %d" % (old, i+12))
open(dst,'wb').write(bytes(b))
print("written", dst, len(b))

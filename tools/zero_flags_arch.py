import struct
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmarch_e.dylib"
b = bytearray(open(p,'rb').read())
i = b.find(struct.pack('>I',0xfade0c02))
old = struct.unpack('>I', b[i+12:i+16])[0]
struct.pack_into('>I', b, i+12, 0)
open(p,'wb').write(bytes(b))
print("qmarch flags 0x%x -> 0x0" % old)

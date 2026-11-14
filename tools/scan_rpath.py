import struct, sys
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmprobe-arm64.dylib"
b = open(p,'rb').read()
magic, cpu, sub, ft, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', b[:32])
off = 32
print("ncmds", ncmds)
for i in range(ncmds):
    cmd, cmdsize = struct.unpack('<II', b[off:off+8])
    if cmd == 0x8000001c:
        name = b[off+12: off+cmdsize].split(b'\0')[0].decode('utf-8','replace')
        print("LC_RPATH", name)
    if cmd in (0xc, 0x8000001f, 0xd):
        name = b[off+8: off+cmdsize].split(b'\0')[0].decode('utf-8','replace')
        print("LC_LOAD(_WEAK)_DYLIB", name)
    off += cmdsize

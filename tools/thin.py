import struct, os
src = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
out = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vendor_thin_arm64.dylib"
b = open(src,'rb').read()
magic, n = struct.unpack('>II', b[:8])
print("fat magic", hex(magic), "slices", n)
for i in range(n):
    cpu, sub, off, size, align = struct.unpack('>iiIII', b[8+20*i: 28+20*i])
    print("  slice", i, "cpu", cpu, "sub", sub, "off", off, "size", size)
    if cpu == 0x0100000c and sub == 0:
        open(out,'wb').write(b[off:off+size])
        print("  -> wrote thin arm64:", size)
print("out exists:", os.path.exists(out), os.path.getsize(out) if os.path.exists(out) else 0)

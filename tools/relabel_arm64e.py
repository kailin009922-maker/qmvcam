#!/usr/bin/env python3
"""把 thin arm64 dylib 的 cpusubtype 改成 arm64e，并修补 CodeDirectory 第 0 页哈希。

只改 4 字节（mach_header_64.cpusubtype），因此只需要重算第 0 页的 SHA-256。
用法: python relabel_arm64e.py <in.dylib> <out.dylib>
"""
import struct, sys, hashlib, shutil, os

CD_MAGIC = 0xfade0c02
SB_MAGIC = 0xfade0cc0

def find_cd(buf):
    i = buf.find(struct.pack('>I', CD_MAGIC))
    while i >= 0:
        length = struct.unpack('>I', buf[i+4:i+8])[0]
        if 8 < length < 0x100000 and i + length <= len(buf):
            return i, length
        i = buf.find(struct.pack('>I', CD_MAGIC), i + 4)
    return None, None

def main(src, dst):
    buf = bytearray(open(src, 'rb').read())
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', buf[:32])
    assert magic == 0xfeedfacf, "not a thin 64-bit Mach-O"
    assert cputype == 0x0100000c, "not arm64"
    old = cpusub
    struct.pack_into('<i', buf, 8, -2147483646)   # 0x80000002 = arm64e
    print("cpusubtype %d -> %d" % (old, -2147483646))

    cd, cdlen = find_cd(buf)
    assert cd, "CodeDirectory not found"
    version, cdflags, hashOffset, identOffset, nSpecial, nCode, codeLimit = \
        struct.unpack('>7I', buf[cd+8: cd+8+28])
    hashSize = buf[cd+36]
    hashType = buf[cd+37]
    platform = buf[cd+38]
    pageSize = buf[cd+39]
    print("CD v%d flags=0x%x hashOff=%d nCode=%d codeLimit=%d hashSize=%d hashType=%d"
          % (version, cdflags, hashOffset, nCode, codeLimit, hashSize, hashType))
    assert hashType == 2, "expect SHA-256"

    page = 4096
    h = hashlib.sha256(bytes(buf[0:min(page, codeLimit)])).digest()
    slot0 = cd + hashOffset
    buf[slot0:slot0+32] = h
    print("page0 hash patched at CD+%d" % hashOffset)

    open(dst, 'wb').write(bytes(buf))
    print("written", dst, os.path.getsize(dst))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

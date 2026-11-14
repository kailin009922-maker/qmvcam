#!/usr/bin/env python3
"""fix_auth_relocs.py — 把 arm64e 目标文件里的 ARM64_RELOC_AUTHENTICATED_POINTER(type=11)
改写成普通 UNSIGNED(type=0)，让 ld64.lld 能完成链接。

背景：Windows 的 ld64.lld 不支持 type 11（报 "INVALID relocation has invalid width of 8 bytes"），
而 Apple 的 ld64 才支持。改写后指针变成普通 8 字节指针——arm64 镜像本来就是这种形式，
arm64e 进程可以运行（ObjC 运行时会自行签名 isa）。

用法: python fix_auth_relocs.py <a.o> [b.o ...]
"""
import struct, sys

LC_SEGMENT_64 = 0x19

def fix(path):
    b = bytearray(open(path, 'rb').read())
    magic = struct.unpack('<I', b[:4])[0]
    assert magic in (0xfeedfacf,), "not MH_MAGIC_64"
    ncmds = struct.unpack('<I', b[16:20])[0]
    off = 32
    patched = 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', b[off:off+8])
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack('<I', b[off+64:off+68])[0]
            sect_off = off + 72
            for _s in range(nsects):
                s = sect_off
                # section_64: sectname[16] segname[16] addr(8) size(8) offset(4) align(4)
                #             reloff(4) nreloc(4) flags(4) reserved1(4) reserved2(4) reserved3(4)
                reloff = struct.unpack('<I', b[s+56:s+60])[0]
                nreloc = struct.unpack('<I', b[s+60:s+64])[0]
                sectname = bytes(b[s:s+16]).split(b'\0')[0].decode('ascii', 'replace')
                for i in range(nreloc):
                    e = reloff + 8 * i
                    word = struct.unpack('<I', b[e+4:e+8])[0]
                    rtype = (word >> 28) & 0xF
                    if rtype == 11:
                        word &= ~(0xF << 28)
                        struct.pack_into('<I', b, e+4, word)
                        patched += 1
                sect_off += 80
        off += cmdsize
    open(path, 'wb').write(bytes(b))
    print("%s: patched %d auth relocs" % (path, patched))
    return patched

if __name__ == '__main__':
    total = 0
    for p in sys.argv[1:]:
        total += fix(p)
    print("total patched:", total)

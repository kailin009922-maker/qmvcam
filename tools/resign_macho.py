#!/usr/bin/env python3
"""resign_macho.py — 就地修补 Mach-O 并重算 CodeDirectory 代码页哈希（ad-hoc 重签）。

支持 fat 与 thin。只重算代码页（slot 0..nCode-1），special slots 原样保留。

用法:
  python resign_macho.py <file> [--minos 16.0]
"""
import struct, sys, hashlib

CD_MAGIC = 0xfade0c02
LC_BUILD_VERSION = 0x32

def slices(buf):
    magic = struct.unpack('>I', buf[:4])[0]
    if magic == 0xcafebabe:
        n = struct.unpack('>I', buf[4:8])[0]
        out = []
        for i in range(n):
            cpu, sub, off, size, align = struct.unpack('>iiIII', buf[8+20*i: 28+20*i])
            out.append((off, size))
        return out
    return [(0, len(buf))]

def patch_minos(buf, base, size, ver):
    major, minor = [int(x) for x in ver.split('.')]
    val = (major << 16) | (minor << 8)
    end = base + size
    off = base + 32
    ncmds = struct.unpack('<I', buf[base+16:base+20])[0]
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', buf[off:off+8])
        if cmd == LC_BUILD_VERSION:
            old = struct.unpack('<I', buf[off+12:off+16])[0]
            struct.pack_into('<I', buf, off+12, val)
            print("  slice@%d minos 0x%06x -> 0x%06x" % (base, old, val))
        off += cmdsize
    return

def resign_slice(buf, base, size):
    """在 slice 内找 CodeDirectory，重算代码页哈希。"""
    start = base
    end = base + size
    i = buf.find(struct.pack('>I', CD_MAGIC), start, end)
    while i >= 0:
        length = struct.unpack('>I', buf[i+4:i+8])[0]
        if 8 < length < 0x200000 and i + length <= end:
            cd = i
            version, flags, hashOff, identOff, nSpecial, nCode, codeLimit = \
                struct.unpack('>7I', buf[cd+8: cd+8+28])
            hashSize = buf[cd+36]
            hashType = buf[cd+37]
            pageSize = buf[cd+39]
            if hashType != 2:
                raise SystemExit("only SHA-256 supported, got %d" % hashType)
            if pageSize == 0:
                pageSize = 4096
            pageSize = 1 << pageSize
            n = 0
            for slot in range(nCode):
                p0 = cd - hashOff  # not used
                page_off = base + slot * pageSize
                if slot * pageSize >= codeLimit:
                    break
                chunk = bytes(buf[page_off: min(page_off + pageSize, base + codeLimit)])
                h = hashlib.sha256(chunk).digest()
                struct.pack_into('<%ds' % hashSize, buf, cd + hashOff + slot*hashSize, h)
                n += 1
            print("  slice@%d resigned %d/%d pages (codeLimit=%d pageSize=%d)"
                  % (base, n, nCode, codeLimit, pageSize))
            return
        i = buf.find(struct.pack('>I', CD_MAGIC), i+4, end)
    raise SystemExit("CodeDirectory not found in slice@%d" % base)

def main():
    path = sys.argv[1]
    minos = None
    if '--minos' in sys.argv:
        minos = sys.argv[sys.argv.index('--minos')+1]
    buf = bytearray(open(path, 'rb').read())
    for base, size in slices(buf):
        if minos:
            patch_minos(buf, base, size, minos)
        resign_slice(buf, base, size)
    open(path, 'wb').write(bytes(buf))
    print("written", path, len(buf))

if __name__ == '__main__':
    main()

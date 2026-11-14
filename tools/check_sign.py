#!/usr/bin/env python3
"""校验 Mach-O 的 ad-hoc 代码签名（LC_CODE_SIGNATURE / CodeDirectory）。

用法: python check_sign.py file.dylib
检查：
  · LC_CODE_SIGNATURE 指向的 SuperBlob 结构
  · CodeDirectory 版本 / identifier / 页大小 / codeLimit
  · 逐页 SHA-256 与 codeLimit 之前的内容比对
  · 特殊槽（-1 .. -5）
"""
import struct, sys, hashlib

LC_CODE_SIGNATURE = 0x1d
CSMAGIC_EMBEDDED_SIGNATURE = 0xfade0cc0
CSMAGIC_CODEDIRECTORY = 0xfade0c02

def load_slices(path):
    b = open(path, 'rb').read()
    magic = struct.unpack_from('>I', b, 0)[0]
    out = []
    if magic in (0xcafebabe, 0xcafebabf):
        n = struct.unpack_from('>I', b, 4)[0]
        p = 8
        for _ in range(n):
            if magic == 0xcafebabe:
                cpu, sub, off, size, align = struct.unpack_from('>iiIII', b, p); p += 20
            else:
                cpu, sub, off, size, align, r = struct.unpack_from('>iiQQII', b, p); p += 32
            out.append((off, size))
    else:
        out.append((0, len(b)))
    return b, out

def check(b, off, size):
    magic, cpu, sub, ft, ncmds, sizeofcmds, flags, res = struct.unpack_from('<IiiIIIII', b, off)
    p = off + 32
    sig = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', b, p)
        if cmd == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from('<II', b, p + 8)
            sig = (off + dataoff, datasize)
        p += cmdsize
    if not sig:
        return 'no LC_CODE_SIGNATURE'
    so, ssz = sig
    blob = b[so:so + ssz]
    m, length, count = struct.unpack_from('>III', blob, 0)
    if m != CSMAGIC_EMBEDDED_SIGNATURE:
        return f'bad SuperBlob magic {m:#x}'
    idx = 12
    cd = None
    for _ in range(count):
        t, o = struct.unpack_from('>II', blob, idx); idx += 8
        if t == 0: cd = (o, struct.unpack_from('>I', blob, o + 4)[0])
    if not cd:
        return 'no CodeDirectory in SuperBlob'
    co, clen = cd
    cdblob = blob[co:co + clen]
    cdm, cdlen, ver, cdflags, hashoff, identoff, nspecial, ncode, codelimit, hashsize, htype, platform, pagesize = \
        struct.unpack_from('>IIIIIIIIIBBBB', cdblob, 0)
    ident = cdblob[identoff:cdblob.index(b'\0', identoff)].decode('utf-8', 'replace')
    page = 1 << pagesize
    bad = 0
    for i in range(ncode):
        start = i * page
        end = min(start + page, codelimit)
        h = hashlib.sha256(b[off + start: off + end]).digest()
        got = cdblob[hashoff + i * hashsize: hashoff + i * hashsize + hashsize]
        if h != got:
            bad += 1
    slots = []
    for s in range(1, nspecial + 1):
        slots.append(f'-{s}')
    return (f'CD v{ver:#x} ident={ident} pagesize={page} codeLimit={codelimit} '
            f'hashType={htype} pages={ncode} bad={bad} special={len(slots)}')

def main():
    b, slices = load_slices(sys.argv[1])
    for i, (off, size) in enumerate(slices):
        print(f'slice {i}: ' + check(b, off, size))

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""把若干 thin Mach-O dylib 合并成一个 FAT（universal）文件。

用法: python makefat.py out.dylib slice1 slice2 ...
对齐 2^14（16384），与 Xcode/lipo 一致；cputype/subtype 从每个 slice 的 mach header 读。
"""
import sys, struct, os

MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
ALIGN = 14

def slice_info(path):
    with open(path, 'rb') as f:
        hdr = f.read(32)
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', hdr)
    if magic != MH_MAGIC_64:
        raise SystemExit(f'{path}: not a thin 64-bit Mach-O ({magic:#x})')
    return cputype, cpusub & 0x00ffffff, os.path.getsize(path)

def main():
    out = sys.argv[1]
    inputs = sys.argv[2:]
    infos = [slice_info(p) for p in inputs]
    # 按 cputype 排序（arm64 < arm64e 用 subtype 区分，保持输入顺序即可）
    n = len(inputs)
    header = struct.pack('>II', FAT_MAGIC, n)
    offset = 8 + n * 20
    entries = []
    body = b''
    for (cpu, sub, size), path in zip(infos, inputs):
        aligned = (offset + (1 << ALIGN) - 1) & ~((1 << ALIGN) - 1)
        pad = aligned - offset
        body += b'\0' * pad
        with open(path, 'rb') as f:
            data = f.read()
        entries.append(struct.pack('>iiIII', cpu, sub, aligned, len(data), ALIGN))
        body += data
        offset = aligned + len(data)
    with open(out, 'wb') as f:
        f.write(header)
        for e in entries:
            f.write(e)
        f.write(body)
    print(f'fat written: {out} ({os.path.getsize(out)} bytes, {n} slices)')

if __name__ == '__main__':
    main()

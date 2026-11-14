#!/usr/bin/env python3
"""把 25r20 的一个日志字符串改一个字节，用于验证注入是否按内容哈希白名单。"""
import shutil

SRC = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
DST = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vendor_1byte.dylib"

shutil.copyfile(SRC, DST)
b = bytearray(open(DST, 'rb').read())
old = b"rotateLeftTapped"
new = b"rotateLeftTappeD"
n = 0
i = b.find(old)
while i >= 0:
    b[i:i+len(old)] = new
    n += 1
    i = b.find(old, i + 1)
open(DST, 'wb').write(bytes(b))
print("patched", n, "occurrences")

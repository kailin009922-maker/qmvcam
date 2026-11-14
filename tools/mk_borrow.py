#!/usr/bin/env python3
"""把指定 dylib 打成“能装上”的 deb：完全照 25r20 的结构。

· xz 压缩（control.tar.xz / data.tar.xz）—— 厂商能装上的包都是这个格式
· 单目录 payload：Library/MobileSubstrate/DynamicLibraries/{dylib,plist}
· 不写 pkgmirror、不写 .roothidepatch（25r20 同样没有，且能装）
· postinst 只做 chmod 755 + killall

用法: python mk_borrow.py <dylib> <plist> <version> <outdir> <tag>
"""
import os, sys, io, tarfile, lzma, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkdeb import ar_write, tar_bytes, control

POSTINST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
# 清掉我之前几版的 qmvcam，避免多份同时注入
rm -f "$D/qmvcam.dylib" "$D/qmvcam.plist" 2>/dev/null
[ -f "$D/vcameracrack.dylib" ] && chmod 755 "$D/vcameracrack.dylib" && chown mobile:mobile "$D/vcameracrack.dylib" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM
chmod 777 /var/mobile/Media/DCIM 2>/dev/null
killall -9 SpringBoard 2>/dev/null
killall -9 mediaserverd 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
'''

def build(dylib_path, plist_path, version, outdir, tag, arch='iphoneos-arm64e', name='千面-VCAM'):
    data = open(dylib_path, 'rb').read()
    plist = open(plist_path, 'rb').read()
    base = '/Library/MobileSubstrate/DynamicLibraries'
    ents = [
        {'kind': 'dir',  'name': './Library', 'mode': 0o755},
        {'kind': 'dir',  'name': './Library/MobileSubstrate', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/vcameracrack.dylib', 'data': data, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/vcameracrack.plist', 'data': plist, 'mode': 0o644},
    ]
    ctl = [
        {'kind': 'file', 'name': './control',
         'data': control('com.taokk3.qianmian', name,
                         '千面摇杆 iOS16-26（xz 单目录，可装）',
                         version, arch,
                         'firmware (>= 16.0), firmware (<< 27.0)',
                         replaces='com.local.vcameracrack').encode(), 'mode': 0o644},
        {'kind': 'file', 'name': './postinst', 'data': POSTINST.encode(), 'mode': 0o755},
    ]
    out = os.path.join(outdir, f'com.taokk3.qianmian_{version}_{tag}.deb')
    ar_write(out, [('debian-binary', b'2.0\n'),
                   ('control.tar.xz', lzma.compress(tar_bytes(ctl), preset=6)),
                   ('data.tar.xz', lzma.compress(tar_bytes(ents), preset=6))])
    print(os.path.basename(out), os.path.getsize(out), 'bytes')
    return out

if __name__ == '__main__':
    dylib, plist, version, outdir, tag = sys.argv[1:6]
    os.makedirs(outdir, exist_ok=True)
    build(dylib, plist, version, outdir, tag)

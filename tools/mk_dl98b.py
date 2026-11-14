#!/usr/bin/env python3
"""打包 4.0.17：我们的 dylib（做 dlopen 诊断）+ 98d 原二进制，只注入 cameracaptured。

风险控制：只进相机进程，即使崩溃也只影响 cameracaptured，不会把 SpringBoard 拖进安全模式。
"""
import io, os, sys, tarfile, lzma, hashlib
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

CI = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\com.taokk3.qianmian_4.0.15.deb"
D98 = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
OUT = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.17_dl98_cam.deb"


def read_ar(p):
    b = open(p, 'rb').read()
    i = 8
    out = {}
    while i + 60 <= len(b):
        n = b[i:i+16].decode('ascii', 'replace').strip()
        s = int(b[i+48:i+58].decode('ascii').strip())
        out[n] = b[i+60:i+60+s]
        i += 60 + s + (s % 2)
    return out


PLIST = b'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Filter</key>
<dict>
\t\t<key>Bundles</key>
\t\t<array>
\t\t\t<string>com.apple.cameracaptured</string>
\t\t</array>
\t\t<key>Executables</key>
\t\t<array>
\t\t\t<string>cameracaptured</string>
\t\t</array>
\t</dict>
</dict>
</plist>
'''

POST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
rm -f "$D/qmvcam.dylib" "$D/qmvcam.plist" "$D/vcameracrack98.dylib" "$D/vcameracrack.dylib" "$D/vcameracrack.plist" 2>/dev/null
chmod 755 "$D/qmvcam.dylib" "$D/vcameracrack98.dylib" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM; chmod 777 /var/mobile/Media/DCIM 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
'''


def main():
    m = read_ar(CI)
    with tarfile.open(fileobj=io.BytesIO(m['data.tar.xz']), mode='r:xz') as tf:
        qm = None
        for x in tf.getmembers():
            if x.name.endswith('qmvcam.dylib'):
                qm = tf.extractfile(x).read()
    d98 = open(D98, 'rb').read()

    base = '/Library/MobileSubstrate/DynamicLibraries'
    ents = [
        {'kind': 'dir',  'name': './Library', 'mode': 0o755},
        {'kind': 'dir',  'name': './Library/MobileSubstrate', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.dylib', 'data': qm, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.plist', 'data': PLIST, 'mode': 0o644},
        {'kind': 'file', 'name': '.' + base + '/vcameracrack98.dylib', 'data': d98, 'mode': 0o755},
    ]
    ctl = [
        {'kind': 'file', 'name': './control',
         'data': control('com.taokk3.qianmian', '千面 诊断(仅相机进程)',
                         'dlopen 98d 并记录 dyld 结果；只注入 cameracaptured',
                         '4.0.17', 'iphoneos-arm64e',
                         'firmware (>= 16.0), firmware (<< 27.0)',
                         replaces='com.local.vcameracrack').encode(), 'mode': 0o644},
        {'kind': 'file', 'name': './postinst', 'data': POST.encode(), 'mode': 0o755},
    ]
    ar_write(OUT, [('debian-binary', b'2.0\n'),
                   ('control.tar.xz', lzma.compress(tar_bytes(ctl), preset=6)),
                   ('data.tar.xz', lzma.compress(tar_bytes(ents), preset=6))])
    print("out:", OUT, os.path.getsize(OUT))
    print("qmvcam size", len(qm), "sha", hashlib.sha256(qm).hexdigest()[:16])
    print("98d    size", len(d98), "sha", hashlib.sha256(d98).hexdigest()[:16])
    print("plist only cameracaptured:", b'cameracaptured' in PLIST and b'springboard' not in PLIST)


if __name__ == '__main__':
    main()

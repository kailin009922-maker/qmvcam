#!/usr/bin/env python3
"""4.0.19：修正 postinst 把自己刚装的文件删掉的问题。

上一版 postinst 里 `rm -f qmvcam.dylib qmvcam.plist` 会把本包刚解包的 payload 删掉，
结果装上等于没装（这就是这几轮"没反应/一行日志都没有"的真正原因）。
"""
import io, os, sys, tarfile, lzma, hashlib
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

CI = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\com.taokk3.qianmian_4.0.17.deb"
D98 = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
PL = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\98d.plist"
OUT = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.19_dl98.deb"


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


POST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
# 只清理旧名字/厂商文件，绝不删本包自己的 payload
rm -f "$D/vcameracrack.dylib" "$D/vcameracrack.plist" 2>/dev/null
chmod 755 "$D/qmvcam.dylib" "$D/vcameracrack98.dylib" 2>/dev/null
chmod 644 "$D/qmvcam.plist" 2>/dev/null
killall -9 SpringBoard 2>/dev/null
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
    pl = open(PL, 'rb').read()

    base = '/Library/MobileSubstrate/DynamicLibraries'
    ents = [
        {'kind': 'dir',  'name': './Library', 'mode': 0o755},
        {'kind': 'dir',  'name': './Library/MobileSubstrate', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.dylib', 'data': qm, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.plist', 'data': pl, 'mode': 0o644},
        {'kind': 'file', 'name': '.' + base + '/vcameracrack98.dylib', 'data': d98, 'mode': 0o755},
    ]
    ctl = [
        {'kind': 'file', 'name': './control',
         'data': control('com.taokk3.qianmian', '千面 诊断',
                         'dlopen 98d；修复 postinst 自删',
                         '4.0.19', 'iphoneos-arm64e',
                         'firmware (>= 16.0), firmware (<< 27.0)',
                         replaces='com.local.vcameracrack').encode(), 'mode': 0o644},
        {'kind': 'file', 'name': './postinst', 'data': POST.encode(), 'mode': 0o755},
    ]
    ar_write(OUT, [('debian-binary', b'2.0\n'),
                   ('control.tar.xz', lzma.compress(tar_bytes(ctl), preset=6)),
                   ('data.tar.xz', lzma.compress(tar_bytes(ents), preset=6))])
    print("out:", OUT, os.path.getsize(OUT))
    print("qmvcam", len(qm), hashlib.sha256(qm).hexdigest()[:16])
    print("98d   ", len(d98), hashlib.sha256(d98).hexdigest()[:16])
    print("postinst deletes own payload?", 'rm -f "$D/qmvcam' in POST)


if __name__ == '__main__':
    main()

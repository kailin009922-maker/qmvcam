#!/usr/bin/env python3
"""mk_macos_deb.py — 把 macOS 编出的 fat dylib 打成可装的 deb。

要点（都是这台设备验证出来的）：
  · xz 压缩（zstd 的包在 roothide 上装不进去）
  · 单目录 payload
  · 文件名必须与 dylib 内 CodeDirectory identifier 一致（qmvcam.dylib）
  · plist 与 dylib 同名
"""
import os, sys, io, tarfile, lzma, time

FILTER = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Filter</key>
\t<dict>
\t\t<key>Bundles</key>
\t\t<array>
\t\t\t<string>com.apple.mediaserverd</string>
\t\t\t<string>com.apple.cameracaptured</string>
\t\t\t<string>com.apple.springboard</string>
\t\t\t<string>com.apple.lskdd</string>
\t\t</array>
\t\t<key>Executables</key>
\t\t<array>
\t\t\t<string>mediaserverd</string>
\t\t\t<string>cameracaptured</string>
\t\t\t<string>SpringBoard</string>
\t\t\t<string>lskdd</string>
\t\t</array>
\t</dict>
</dict>
</plist>
'''

CONTROL = '''Package: com.taokk3.qianmian
Name: 千面-VCAM
Description: 千面摇杆 自编译版（iOS 16-26，arm64+arm64e）
Maintainer: Local
Author: Local
Section: Tweaks
Depends: firmware (>= 16.0), firmware (<< 27.0)
Architecture: iphoneos-arm64e
Version: {ver}
Installed-Size: 2200
'''

POSTINST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
rm -f "$D/vcameracrack.dylib" "$D/vcameracrack.plist" 2>/dev/null
chmod 755 "$D/qmvcam.dylib" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM
chmod 777 /var/mobile/Media/DCIM 2>/dev/null
killall -9 SpringBoard 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
'''


def ar_write(path, members):
    with open(path, 'wb') as f:
        f.write(b'!<arch>\n')
        for name, data in members:
            hdr = '{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n'.format(
                name, '0', '0', '0', '100644', str(len(data))).encode()
            f.write(hdr); f.write(data)
            if len(data) % 2:
                f.write(b'\n')


def tar_bytes(entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tf:
        for e in entries:
            ti = tarfile.TarInfo(e['name'])
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = 'root'
            ti.mode = e.get('mode', 0o644)
            ti.mtime = int(time.time())
            if e['kind'] == 'dir':
                ti.type = tarfile.DIRTYPE
                ti.mode = e.get('mode', 0o755)
                tf.addfile(ti)
            else:
                ti.size = len(e['data'])
                tf.addfile(ti, io.BytesIO(e['data']))
    return buf.getvalue()


def main():
    fat = sys.argv[1]
    ver = sys.argv[2] if len(sys.argv) > 2 else '4.0.0'
    outdir = 'dist'
    os.makedirs(outdir, exist_ok=True)
    data = open(fat, 'rb').read()

    base = '/Library/MobileSubstrate/DynamicLibraries'
    entries = [
        {'kind': 'dir',  'name': './Library', 'mode': 0o755},
        {'kind': 'dir',  'name': './Library/MobileSubstrate', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.dylib', 'data': data, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/qmvcam.plist', 'data': FILTER.encode(), 'mode': 0o644},
    ]
    ctl = [
        {'kind': 'file', 'name': './control',
         'data': CONTROL.format(ver=ver).encode(), 'mode': 0o644},
        {'kind': 'file', 'name': './postinst', 'data': POSTINST.encode(), 'mode': 0o755},
    ]
    out = os.path.join(outdir, 'com.taokk3.qianmian_%s.deb' % ver)
    ar_write(out, [('debian-binary', b'2.0\n'),
                   ('control.tar.xz', lzma.compress(tar_bytes(ctl), preset=6)),
                   ('data.tar.xz', lzma.compress(tar_bytes(entries), preset=6))])
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()

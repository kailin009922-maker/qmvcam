#!/usr/bin/env python3
"""打包重编译版 deb（iOS 16-26，单目录 payload）。

用法: python mkdeb.py <qmvcam.dylib> [outdir]
产出:
  com.taokk3.qianmian_3.0.2-src_roothide.deb
  com.taokk3.qianmian_3.0.2-src_rootless.deb

注意：
  · payload 只有一个目录（Library/MobileSubstrate/DynamicLibraries），
    不带 pkgmirror 镜像 —— 双份 dylib 在 roothide 下会被展开成不一致的两份，曾导致白苹果。
  · postinst 会 chmod 755（dlopen 失败会闪退）。
"""
import os, sys, io, tarfile, time
import zstandard

AR_MAGIC = b'!<arch>\n'

def ar_write(path, members):
    with open(path, 'wb') as f:
        f.write(AR_MAGIC)
        for name, data in members:
            hdr = '{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n'.format(
                name, '0', '0', '0', '100644', str(len(data))).encode()
            f.write(hdr)
            f.write(data)
            if len(data) % 2:
                f.write(b'\n')

def tar_bytes(entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tf:
        for e in entries:
            ti = tarfile.TarInfo(name=e['name'])
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = 'root'
            ti.mode = e.get('mode', 0o644)
            ti.mtime = e.get('mtime', int(time.time()))
            if e['kind'] == 'dir':
                ti.type = tarfile.DIRTYPE
                ti.mode = e.get('mode', 0o755)
                tf.addfile(ti)
            elif e['kind'] == 'sym':
                ti.type = tarfile.SYMTYPE
                ti.linkname = e['target']
                ti.mode = 0o777
                tf.addfile(ti)
            else:
                data = e['data']
                ti.size = len(data)
                tf.addfile(ti, io.BytesIO(data))
    return buf.getvalue()

def build_deb(out, control_text, data_entries, control_entries=None):
    ctl = [{'kind': 'file', 'name': './control', 'data': control_text.encode(), 'mode': 0o644}]
    ctl += (control_entries or [])
    c_plain = tar_bytes(ctl)
    d_plain = tar_bytes(data_entries)
    c = zstandard.ZstdCompressor(level=19).compress(c_plain)
    d = zstandard.ZstdCompressor(level=19).compress(d_plain)
    ar_write(out, [('debian-binary', b'2.0\n'),
                   ('control.tar.zst', c),
                   ('data.tar.zst', d)])
    print(f'{os.path.basename(out)}  {os.path.getsize(out)} bytes')

def control(pkg, name, desc, version, arch, depends, replaces=None):
    lines = [
        f'Package: {pkg}',
        f'Name: {name}',
        f'Description: {desc}',
        'Maintainer: Local',
        'Author: Local',
        'Section: Tweaks',
        f'Depends: {depends}',
        f'Architecture: {arch}',
        f'Version: {version}',
        'Installed-Size: 2100',
    ]
    if replaces:
        lines.append(f'Replaces: {replaces}')
        lines.append(f'Conflicts: {replaces}')
        lines.append(f'Provides: {replaces}')
    return '\n'.join(lines) + '\n'

DEBIAN_FILTER = '''<?xml version="1.0" encoding="UTF-8"?>
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
\t\t</array>
\t\t<key>Executables</key>
\t\t<array>
\t\t\t<string>mediaserverd</string>
\t\t\t<string>cameracaptured</string>
\t\t\t<string>SpringBoard</string>
\t\t</array>
\t</dict>
</dict>
</plist>
'''

def postinst(dylib_name, root_prefix):
    return '''#!/bin/sh
P="%s/Library/MobileSubstrate/DynamicLibraries/%s"
[ -f "$P" ] && chmod 755 "$P" && chown mobile:mobile "$P" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM/vcam /var/mobile/Media/DCIM/2 /var/mobile/Media/DCIM/4
chmod 777 /var/mobile/Media/DCIM/vcam /var/mobile/Media/DCIM/2 /var/mobile/Media/DCIM/4 2>/dev/null
killall -9 SpringBoard 2>/dev/null
killall -9 mediaserverd 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
''' % (root_prefix, dylib_name)

def entries_single(prefix, name, data):
    base = prefix + '/Library/MobileSubstrate/DynamicLibraries'
    return [
        {'kind': 'dir',  'name': '.' + prefix + '/Library', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + prefix + '/Library/MobileSubstrate', 'mode': 0o755},
        {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/' + name, 'data': data, 'mode': 0o755},
        {'kind': 'file', 'name': '.' + base + '/' + name.replace('.dylib', '.plist'),
         'data': DEBIAN_FILTER.encode(), 'mode': 0o644},
    ]

def main():
    rebuild = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else 'dist'
    os.makedirs(outdir, exist_ok=True)
    rd = open(rebuild, 'rb').read()

    deps = 'mobilesubstrate | ellekit | libhooker | substitute, firmware (>= 16.0), firmware (<< 27.0)'

    c = control('com.taokk3.qianmian', '千面-VCAM',
                '千面摇杆 自编译版（iOS 16-26，源码重编译 + 授权自持）',
                '3.0.2', 'iphoneos-arm64e', deps, replaces='com.local.vcameracrack')
    build_deb(os.path.join(outdir, 'com.taokk3.qianmian_3.0.2-src_roothide.deb'),
              c, entries_single('', 'qmvcam.dylib', rd),
              [{'kind': 'file', 'name': './postinst',
                'data': postinst('qmvcam.dylib', '').encode(), 'mode': 0o755}])

    c2 = control('com.taokk3.qianmian', '千面-VCAM',
                 '千面摇杆 自编译版（iOS 16-26，rootless 布局）',
                 '3.0.2', 'iphoneos-arm64', deps, replaces='com.local.vcameracrack')
    build_deb(os.path.join(outdir, 'com.taokk3.qianmian_3.0.2-src_rootless.deb'),
              c2, entries_single('/var/jb', 'qmvcam.dylib', rd),
              [{'kind': 'file', 'name': './postinst',
                'data': postinst('qmvcam.dylib', '/var/jb').encode(), 'mode': 0o755}])

if __name__ == '__main__':
    main()

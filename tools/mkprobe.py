#!/usr/bin/env python3
"""打包“探针”deb：只写诊断信标，不挂钩子、不建窗口。

用法: python mkprobe.py <qmprobe.dylib> [outdir]
产出: com.taokk3.qianmian_3.1.0-probe_roothide.deb / _rootless.deb
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkdeb import build_deb, control, tar_bytes, entries_single

PROBE_PLIST = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Filter</key>
<dict>
\t\t<key>Bundles</key>
\t\t<array>
\t\t\t<string>com.apple.springboard</string>
\t\t\t<string>com.apple.mediaserverd</string>
\t\t\t<string>com.apple.cameracaptured</string>
\t\t</array>
\t\t<key>Executables</key>
\t\t<array>
\t\t\t<string>SpringBoard</string>
\t\t\t<string>mediaserverd</string>
\t\t\t<string>cameracaptured</string>
\t\t</array>
\t</dict>
</dict>
</plist>
'''

POSTINST = '''#!/bin/sh
# 先清掉旧厂商 dylib，避免双份注入（vcameracrack 与 qmvcam 同时存在会崩）
for R in "" "/var/jb"; do
  D="$R/Library/MobileSubstrate/DynamicLibraries"
  [ -d "$D" ] || continue
  rm -f "$D/vcameracrack.dylib" "$D/vcameracrack.plist"
  chmod 755 "$D/qmvcam.dylib" 2>/dev/null
  chown mobile:mobile "$D/qmvcam.dylib" 2>/dev/null
done
mkdir -p /var/mobile/Media/DCIM
chmod 777 /var/mobile/Media/DCIM 2>/dev/null
echo "QianMian probe installed. respring now." > /var/mobile/Media/DCIM/.qm_probe_installed
killall -9 SpringBoard 2>/dev/null
exit 0
'''

def main():
    dylib = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else 'dist'
    os.makedirs(outdir, exist_ok=True)
    data = open(dylib, 'rb').read()

    deps = 'firmware (>= 16.0), firmware (<< 27.0)'

    for prefix, arch, tag in (('', 'iphoneos-arm64e', 'roothide'),
                              ('/var/jb', 'iphoneos-arm64', 'rootless')):
        base = prefix + '/Library/MobileSubstrate/DynamicLibraries'
        ents = [
            {'kind': 'dir',  'name': '.' + prefix + '/Library', 'mode': 0o755},
            {'kind': 'dir',  'name': '.' + prefix + '/Library/MobileSubstrate', 'mode': 0o755},
            {'kind': 'dir',  'name': '.' + base, 'mode': 0o755},
            {'kind': 'file', 'name': '.' + base + '/qmvcam.dylib', 'data': data, 'mode': 0o755},
            {'kind': 'file', 'name': '.' + base + '/qmvcam.plist',
             'data': PROBE_PLIST.encode(), 'mode': 0o644},
        ]
        c = control('com.taokk3.qianmian', '千面-VCAM (诊断探针)',
                    '只写诊断信标，不挂钩子不建窗口（排障用，可随时卸载）',
                    '3.1.0-probe', arch, deps, replaces='com.local.vcameracrack')
        out = os.path.join(outdir, f'com.taokk3.qianmian_3.1.0-probe_{tag}.deb')
        build_deb(out, c, ents,
                  [{'kind': 'file', 'name': './postinst',
                    'data': POSTINST.encode(), 'mode': 0o755}])

if __name__ == '__main__':
    main()

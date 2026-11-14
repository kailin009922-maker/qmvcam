import os, sys, io, tarfile, lzma
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

DYL = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib","rb").read()

def plist(bundles, execs):
    b = "\n".join("\t\t\t<string>%s</string>" % x for x in bundles)
    e = "\n".join("\t\t\t<string>%s</string>" % x for x in execs)
    return ('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Filter</key>
\t<dict>
\t\t<key>Bundles</key>
\t\t<array>
%s
\t\t</array>
\t\t<key>Executables</key>
\t\t<array>
%s
\t\t</array>
\t</dict>
</dict>
</plist>
''' % (b, e)).encode()

POSTINST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
for n in qmvcam qmprobe qmarch; do rm -f "$D/$n.dylib" "$D/$n.plist" 2>/dev/null; done
chmod 755 "$D/vcameracrack.dylib" 2>/dev/null
killall -9 SpringBoard 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
'''

variants = [
  ("3.8.0", "cam_only",    ["com.apple.cameracaptured"], ["cameracaptured"]),
  ("3.8.1", "cam_sb",      ["com.apple.cameracaptured","com.apple.springboard"], ["cameracaptured","SpringBoard"]),
]
base='/Library/MobileSubstrate/DynamicLibraries'
for ver, tag, bundles, execs in variants:
    ents=[{'kind':'dir','name':'./Library','mode':0o755},
          {'kind':'dir','name':'./Library/MobileSubstrate','mode':0o755},
          {'kind':'dir','name':'.'+base,'mode':0o755},
          {'kind':'file','name':'.'+base+'/vcameracrack.dylib','data':DYL,'mode':0o755},
          {'kind':'file','name':'.'+base+'/vcameracrack.plist','data':plist(bundles,execs),'mode':0o644}]
    ctl=[{'kind':'file','name':'./control','data':control('com.taokk3.qianmian','千面-VCAM',
         '25r20 原码 + 注入面裁剪（%s）' % tag, ver,'iphoneos-arm64e',
         'firmware (>= 16.0), firmware (<< 27.0)', replaces='com.local.vcameracrack').encode(),'mode':0o644},
         {'kind':'file','name':'./postinst','data':POSTINST.encode(),'mode':0o755}]
    out=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_%s_%s.deb" % (ver, tag)
    ar_write(out,[('debian-binary',b'2.0\n'),
                  ('control.tar.xz',lzma.compress(tar_bytes(ctl),preset=6)),
                  ('data.tar.xz',lzma.compress(tar_bytes(ents),preset=6))])
    print(out, os.path.getsize(out))

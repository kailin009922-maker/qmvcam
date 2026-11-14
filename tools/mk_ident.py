import os, sys, io, tarfile, lzma
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

VEND_PLIST = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.plist","rb").read()
data = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmprobe-arm64.dylib","rb").read()

POSTINST = '''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
rm -f "$D/vcameracrack.dylib" "$D/vcameracrack.plist" "$D/qmvcam.dylib" "$D/qmvcam.plist" 2>/dev/null
chmod 755 "$D/qmprobe.dylib" 2>/dev/null
chown mobile:mobile "$D/qmprobe.dylib" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM
chmod 777 /var/mobile/Media/DCIM 2>/dev/null
date +"%Y-%m-%d %H:%M:%S postinst ran" > /var/mobile/Media/DCIM/.qm_probe_installed
chmod 666 /var/mobile/Media/DCIM/.qm_probe_installed 2>/dev/null
killall -9 SpringBoard 2>/dev/null
killall -9 cameracaptured 2>/dev/null
exit 0
'''

base = '/Library/MobileSubstrate/DynamicLibraries'
ents = [
    {'kind':'dir','name':'./Library','mode':0o755},
    {'kind':'dir','name':'./Library/MobileSubstrate','mode':0o755},
    {'kind':'dir','name':'.'+base,'mode':0o755},
    # 关键：payload 文件名与 dylib 内的 CodeDirectory identifier 完全一致
    {'kind':'file','name':'.'+base+'/qmprobe.dylib','data':data,'mode':0o755},
    {'kind':'file','name':'.'+base+'/qmprobe.plist','data':VEND_PLIST,'mode':0o644},
]
ctl = [
    {'kind':'file','name':'./control','data':control('com.taokk3.qianmian.probe','千面探针(标识一致)',
        '只写诊断信标；文件名与 CD 标识一致，验证注入链','3.3.2','iphoneos-arm64e',
        'firmware (>= 16.0), firmware (<< 27.0)').encode(),'mode':0o644},
    {'kind':'file','name':'./postinst','data':POSTINST.encode(),'mode':0o755},
]
out = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qmprobe_ident_match.deb"
ar_write(out, [('debian-binary', b'2.0\n'),
               ('control.tar.xz', lzma.compress(tar_bytes(ctl), preset=6)),
               ('data.tar.xz', lzma.compress(tar_bytes(ents), preset=6))])
print(out, os.path.getsize(out))

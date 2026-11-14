import os, sys, io, tarfile, lzma
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control
PL = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-ios26\_roothide_隐藏根_千面iOS26_25r20.deb\Library\MobileSubstrate\DynamicLibraries\vcameracrack.plist","rb").read()
D  = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmarch_e.dylib","rb").read()
base='/Library/MobileSubstrate/DynamicLibraries'
ents=[{'kind':'dir','name':'./Library','mode':0o755},
      {'kind':'dir','name':'./Library/MobileSubstrate','mode':0o755},
      {'kind':'dir','name':'.'+base,'mode':0o755},
      {'kind':'file','name':'.'+base+'/qmarch.dylib','data':D,'mode':0o755},
      {'kind':'file','name':'.'+base+'/qmarch.plist','data':PL,'mode':0o644}]
POST='''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
rm -f "$D/vcameracrack.dylib" "$D/vcameracrack.plist" "$D/qmvcam.dylib" "$D/qmvcam.plist" "$D/qmprobe.dylib" "$D/qmprobe.plist" 2>/dev/null
chmod 755 "$D/qmarch.dylib" 2>/dev/null
killall -9 SpringBoard 2>/dev/null
exit 0
'''
ctl=[{'kind':'file','name':'./control','data':control('com.taokk3.qianmian','千面-VCAM',
     'arm64e C-only 探针（写 /DCIM/.qm_arch.txt）','5.1.0','iphoneos-arm64e',
     'firmware (>= 16.0), firmware (<< 27.0)', replaces='com.local.vcameracrack').encode(),'mode':0o644},
     {'kind':'file','name':'./postinst','data':POST.encode(),'mode':0o755}]
out=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_5.1.0_archprobe.deb"
ar_write(out,[('debian-binary',b'2.0\n'),
              ('control.tar.xz',lzma.compress(tar_bytes(ctl),preset=6)),
              ('data.tar.xz',lzma.compress(tar_bytes(ents),preset=6))])
print(out, os.path.getsize(out))

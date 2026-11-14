import io, os, sys, tarfile, lzma, struct
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

CI = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\com.taokk3.qianmian_4.0.15.deb"
D98 = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm\.pkg_data\Library\MobileSubstrate\DynamicLibraries\vcameracrack.dylib"
OUT = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.16_dl98.deb"

def read_ar(p):
    b=open(p,'rb').read(); i=8; out={}
    while i+60<=len(b):
        n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
        out[n]=b[i+60:i+60+s]; i+=60+s+(s%2)
    return out

m=read_ar(CI)
# 取出 CI 包里的 qmvcam.dylib
with tarfile.open(fileobj=io.BytesIO(m['data.tar.xz']), mode='r:xz') as tf:
    qm=None
    for x in tf.getmembers():
        if x.name.endswith('qmvcam.dylib'): qm=tf.extractfile(x).read()
print("qmvcam.dylib:", len(qm), " 98d:", os.path.getsize(D98))

base='/Library/MobileSubstrate/DynamicLibraries'
ctl_plist = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\98d.plist","rb").read()
POST='''#!/bin/sh
D="/Library/MobileSubstrate/DynamicLibraries"
rm -f "$D/qmvcam.dylib" "$D/qmvcam.plist" "$D/vcameracrack98.dylib" "$D/vcameracrack.dylib" "$D/vcameracrack.plist" 2>/dev/null
chmod 755 "$D/qmvcam.dylib" "$D/vcameracrack98.dylib" 2>/dev/null
mkdir -p /var/mobile/Media/DCIM
chmod 777 /var/mobile/Media/DCIM 2>/dev/null
killall -9 SpringBoard 2>/dev/null
exit 0
'''
ents=[
 {'kind':'dir','name':'./Library','mode':0o755},
 {'kind':'dir','name':'./Library/MobileSubstrate','mode':0o755},
 {'kind':'dir','name':'.'+base,'mode':0o755},
 {'kind':'file','name':'.'+base+'/qmvcam.dylib','data':qm,'mode':0o755},
 {'kind':'file','name':'.'+base+'/qmvcam.plist','data':ctl_plist,'mode':0o644},
 {'kind':'file','name':'.'+base+'/vcameracrack98.dylib','data':open(D98,'rb').read(),'mode':0o755},
]
ctl=[{'kind':'file','name':'./control','data':control('com.taokk3.qianmian','千面-VCAM 诊断',
     'dlopen 98d 并记录 dyld 错误','4.0.16','iphoneos-arm64e',
     'firmware (>= 16.0), firmware (<< 27.0)', replaces='com.local.vcameracrack').encode(),'mode':0o644},
     {'kind':'file','name':'./postinst','data':POST.encode(),'mode':0o755}]
ar_write(OUT,[('debian-binary',b'2.0\n'),
              ('control.tar.xz',lzma.compress(tar_bytes(ctl),preset=6)),
              ('data.tar.xz',lzma.compress(tar_bytes(ents),preset=6))])
print(OUT, os.path.getsize(OUT))

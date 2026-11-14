import os, sys, io, tarfile, lzma
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control

DYL = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\98d_minos16.dylib","rb").read()
PL  = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\98d.plist","rb").read()
base='/Library/MobileSubstrate/DynamicLibraries'
ents=[
 {'kind':'dir','name':'.','mode':0o755},
 {'kind':'dir','name':'./Library','mode':0o755},
 {'kind':'dir','name':'./Library/MobileSubstrate','mode':0o755},
 {'kind':'dir','name':'.'+base,'mode':0o755},
 {'kind':'file','name':'.'+base+'/vcameracrack.dylib','data':DYL,'mode':0o755},
 {'kind':'file','name':'.'+base+'/vcameracrack.plist','data':PL,'mode':0o644},
 # 关键：原包就带这个 0 字节标记，告诉 roothide 「这支 dylib 需要打路径补丁」
 {'kind':'file','name':'.'+base+'/vcameracrack.dylib.roothidepatch','data':b'','mode':0o755},
]
ctl=[{'kind':'file','name':'./control','data':control('com.taokk3.qianmian','千面-VCAM',
     '98d 原码 + minos16 + roothidepatch 标记','3.9.1','iphoneos-arm64e',
     'firmware (>= 16.0), firmware (<< 27.0)', replaces='com.local.vcameracrack').encode(),'mode':0o644}]
out=r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_3.9.1_98d_patch.deb"
ar_write(out,[('debian-binary',b'2.0\n'),
              ('control.tar.xz',lzma.compress(tar_bytes(ctl),preset=6)),
              ('data.tar.xz',lzma.compress(tar_bytes(ents),preset=6))])
print(out, os.path.getsize(out))

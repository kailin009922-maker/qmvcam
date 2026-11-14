import os, sys, io, tarfile, lzma, time, hashlib
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write, tar_bytes, control
from mkprobe import PROBE_PLIST, POSTINST

data = open(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\qmprobe-arm64.dylib","rb").read()

def build(out, prefix, arch, tag):
    base = prefix + '/Library/MobileSubstrate/DynamicLibraries'
    ents = [
        {'kind':'dir','name':'.'+prefix+'/Library','mode':0o755},
        {'kind':'dir','name':'.'+prefix+'/Library/MobileSubstrate','mode':0o755},
        {'kind':'dir','name':'.'+base,'mode':0o755},
        {'kind':'file','name':'.'+base+'/qmvcam.dylib','data':data,'mode':0o755},
        {'kind':'file','name':'.'+base+'/qmvcam.plist','data':PROBE_PLIST.encode(),'mode':0o644},
    ]
    ctl = [{'kind':'file','name':'./control',
            'data':control('com.taokk3.qianmian','千面-VCAM (诊断探针)',
                           '只写诊断信标，不挂钩子不建窗口（排障用）',
                           '3.1.1-probe', arch, 'firmware (>= 16.0), firmware (<< 27.0)',
                           replaces='com.local.vcameracrack').encode(),'mode':0o644},
           {'kind':'file','name':'./postinst','data':POSTINST.encode(),'mode':0o755}]
    cp = tar_bytes(ctl); dp = tar_bytes(ents)
    ar_write(out, [('debian-binary', b'2.0\n'),
                   ('control.tar.xz', lzma.compress(cp, preset=6)),
                   ('data.tar.xz', lzma.compress(dp, preset=6))])
    print(os.path.basename(out), os.path.getsize(out))

build(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\probe_xz_roothide.deb", '', 'iphoneos-arm64e','roothide')
build(r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\probe_xz_rootless.deb", '/var/jb', 'iphoneos-arm64','rootless')

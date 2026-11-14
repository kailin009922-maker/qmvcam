import io, tarfile, lzma, struct, sys, os
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\com.taokk3.qianmian_4.0.0.deb"
b=open(p,'rb').read(); i=8; dylib=None
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    print("member", n, s)
    if n.endswith('.xz'):
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                print("   ", m.name, m.size, oct(m.mode))
                if m.name.endswith('.dylib'):
                    dylib=tf.extractfile(m).read()
open(r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\qmvcam.dylib","wb").write(dylib)
# fat?
magic=struct.unpack('>I', dylib[:4])[0]
print("fat magic:", hex(magic))
if magic==0xcafebabe:
    n=struct.unpack('>I', dylib[4:8])[0]
    for k in range(n):
        cpu,sub,off,size,align=struct.unpack('>iiIII', dylib[8+20*k:28+20*k])
        print("  slice",k,"cpu",cpu,"sub",sub,"size",size)

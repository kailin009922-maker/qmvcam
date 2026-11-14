import io, tarfile, struct
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\com.taokk3.qianmian_4.0.0.deb"
b=open(p,'rb').read(); i=8; dyl=None
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    if n=='data.tar.xz':
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                if m.name.endswith('.dylib'): dyl=tf.extractfile(m).read()
open(r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\qmvcam2.dylib","wb").write(dyl)
magic=struct.unpack('>I', dyl[:4])[0]; print("fat:", hex(magic))
n=struct.unpack('>I', dyl[4:8])[0]
for k in range(n):
    cpu,sub,off,size,align=struct.unpack('>iiIII', dyl[8+20*k:28+20*k]); print(" slice",k,cpu,sub,size)

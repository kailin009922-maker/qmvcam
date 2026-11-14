import io, tarfile, struct
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.17_dl98_cam.deb"
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    if n=='data.tar.xz':
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                if m.name.endswith('qmvcam.dylib'):
                    x=tf.extractfile(m).read()
                    open(r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\qm417.dylib","wb").write(x)
                    magic=struct.unpack('>I',x[:4])[0]; print("fat", hex(magic))
                    if magic==0xcafebabe:
                        cnt=struct.unpack('>I',x[4:8])[0]
                        for k in range(cnt):
                            cpu,sub,off,size,al=struct.unpack('>iiIII', x[8+20*k:28+20*k]); print("  slice",k,cpu,sub,size)

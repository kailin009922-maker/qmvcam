import io, tarfile
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.18_dl98_all.deb"
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    if n=='data.tar.xz':
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                if m.name.endswith('qmvcam.dylib'):
                    open(r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\qm418.dylib","wb").write(tf.extractfile(m).read())

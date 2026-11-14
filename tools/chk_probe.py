import io, tarfile
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qmprobe_ident_match.deb"
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    name=b[i:i+16].decode('ascii','replace').strip(); size=int(b[i+48:i+58].decode('ascii').strip())
    data=b[i+60:i+60+size]; i+=60+size+(size%2)
    print("member", name, size)
    if name.endswith('.xz'):
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as tf:
            for m in tf.getmembers():
                print("   ", m.name, m.size, oct(m.mode))

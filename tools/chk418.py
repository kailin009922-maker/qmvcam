import io, tarfile, struct, hashlib
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_4.0.18_dl98_all.deb"
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    if n.endswith('.xz'):
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                print("  %-70s %8d %s" % (m.name, m.size, oct(m.mode)))
                if m.name.endswith('qmvcam.dylib'):
                    x=tf.extractfile(m).read()
                    magic=struct.unpack('>I',x[:4])[0]
                    cnt=struct.unpack('>I',x[4:8])[0]
                    print("     fat=%s slices=%d" % (hex(magic), cnt))
                    for k in range(cnt):
                        cpu,sub,off,size,al=struct.unpack('>iiIII', x[8+20*k:28+20*k]); print("       slice%d cpu=%d sub=%d size=%d" % (k,cpu,sub,size))
                if m.name.endswith('qmvcam.plist'):
                    txt=tf.extractfile(m).read().decode()
                    print("     plist 进程:", [l.strip() for l in txt.splitlines() if '<string>' in l])

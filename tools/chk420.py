import io, os, tarfile, struct
p=os.environ['DEBPATH']
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    if n.endswith('.xz'):
        with tarfile.open(fileobj=io.BytesIO(d), mode='r:xz') as tf:
            for m in tf.getmembers():
                print("  %-64s %8d %s" % (m.name, m.size, oct(m.mode)))
                if m.name.endswith('qmvcam.dylib'):
                    x=tf.extractfile(m).read()
                    open(r"D:\Backup\Documents\deepseek-harness\default-workspace\ci_out\qm420.dylib","wb").write(x)
                    cnt=struct.unpack('>I',x[4:8])[0]
                    for k in range(cnt):
                        cpu,sub,off,size,al=struct.unpack('>iiIII', x[8+20*k:28+20*k]); print("     slice%d sub=%d size=%d" % (k,sub,size))
                if m.name.endswith('postinst'):
                    for line in tf.extractfile(m).read().decode().splitlines(): print("     | "+line)

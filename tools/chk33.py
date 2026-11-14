import io, tarfile
def read_ar(path):
    b=open(path,'rb').read(); p=8; out=[]
    while p+60<=len(b):
        name=b[p:p+16].decode('ascii','replace').strip(); size=int(b[p+48:p+58].decode('ascii').strip())
        out.append((name,b[p+60:p+60+size])); p+=60+size+(size%2)
    return out
for p in ("dist/com.taokk3.qianmian_3.3.0_probe_as_vcr.deb","dist/com.taokk3.qianmian_3.3.1_build_as_vcr.deb"):
    for name,data in read_ar(p):
        if name=='data.tar.xz':
            with tarfile.open(fileobj=io.BytesIO(data),mode='r:xz') as tf:
                for m in tf.getmembers():
                    if m.isfile(): print(p.split('_')[-1], m.name, m.size, oct(m.mode))

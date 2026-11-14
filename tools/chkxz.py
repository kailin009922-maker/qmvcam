import sys, io, tarfile, struct, os
def read_ar(path):
    b=open(path,'rb').read()
    assert b[:8]==b'!<arch>\n'
    p=8; out=[]
    while p+60<=len(b):
        name=b[p:p+16].decode('ascii','replace').strip()
        size=int(b[p+48:p+58].decode('ascii').strip())
        data=b[p+60:p+60+size]
        out.append((name,data))
        p += 60+size+(size%2)
    return out
for p in ("dist/probe_xz_roothide.deb",):
    print("==", p)
    for name,data in read_ar(p):
        print("  member", name, len(data))
        if name.endswith('.xz'):
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:xz") as tf:
                for m in tf.getmembers():
                    print("     ", m.name, m.size, oct(m.mode))

import io, os, tarfile, lzma, sys, time
sys.path.insert(0, r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\tools")
from mkdeb import ar_write

SRC = r"C:\Users\Administrator\Desktop\千面发卡器\【roothide·隐藏根】千面iOS26_25r20.deb"
DYL = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build\vcameracrack-arm64.dylib"
OUT = r"D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\dist\qm_3.4.0_r20shell.deb"

def read_ar(path):
    b = open(path,'rb').read(); p=8; out=[]
    while p+60<=len(b):
        name=b[p:p+16].decode('ascii','replace').strip()
        size=int(b[p+48:p+58].decode('ascii').strip())
        out.append((name, b[p+60:p+60+size]))
        p += 60+size+(size%2)
    return out

members = dict(read_ar(SRC))
print("members:", list(members))

def unpack(data):
    tf = tarfile.open(fileobj=io.BytesIO(data), mode='r:xz')
    items = []
    for m in tf.getmembers():
        items.append((m, tf.extractfile(m).read() if m.isfile() else None))
    tf.close()
    return items

def pack(items):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tf:
        for m, data in items:
            ti = tarfile.TarInfo(m.name)
            ti.mode = m.mode; ti.uid = ti.gid = 0; ti.uname = ti.gname = 'root'
            ti.mtime = int(time.time())
            if m.isdir():
                ti.type = tarfile.DIRTYPE; tf.addfile(ti)
            else:
                ti.size = len(data); tf.addfile(ti, io.BytesIO(data))
    return lzma.compress(buf.getvalue(), preset=6)

new_ctl = []
for m, d in unpack(members['control.tar.xz']):
    if m.name.endswith('control'):
        out = []
        for ln in d.decode().splitlines():
            out.append('Version: 3.4.0' if ln.startswith('Version:') else ln)
        d = ('\n'.join(out) + '\n').encode()
        print("control:\n" + d.decode())
    new_ctl.append((m, d))

newdyl = open(DYL,'rb').read()
new_data = []
for m, d in unpack(members['data.tar.xz']):
    if m.name.endswith('vcameracrack.dylib'):
        print("swap dylib:", len(d), "->", len(newdyl))
        d = newdyl; m.size = len(d); m.mode = 0o755
    new_data.append((m, d))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
ar_write(OUT, [('debian-binary', b'2.0\n'),
               ('control.tar.xz', pack(new_ctl)),
               ('data.tar.xz', pack(new_data))])
print("out:", OUT, os.path.getsize(OUT))

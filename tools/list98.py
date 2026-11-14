import io, tarfile, zstandard, lzma
p = r"C:\Users\Administrator\Desktop\千面发卡器\【发这个】千面摇杆_iOS15-17.3_98d.deb"
b=open(p,'rb').read(); i=8
while i+60<=len(b):
    n=b[i:i+16].decode('ascii','replace').strip(); s=int(b[i+48:i+58].decode('ascii').strip())
    d=b[i+60:i+60+s]; i+=60+s+(s%2)
    print("member", n, s)
    if n.startswith('data.tar'):
        raw = zstandard.ZstdDecompressor().decompress(d) if n.endswith('.zst') else lzma.decompress(d)
        with tarfile.open(fileobj=io.BytesIO(raw)) as tf:
            for m in tf.getmembers():
                print("   %-72s %8d %s" % (m.name, m.size, oct(m.mode)))

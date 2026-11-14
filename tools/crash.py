import json, glob, os, sys
d = r"D:\Backup\Documents\deepseek-harness\default-workspace\dev_crash_now"
for p in sorted(glob.glob(os.path.join(d,"SpringBoard-*.ips")))[-4:]:
    txt = open(p, encoding='utf-8', errors='replace').read()
    # .ips: 第一行 JSON 头，第二段 JSON 体
    i = txt.find('\n')
    try:
        body = json.loads(txt[i+1:])
    except Exception as e:
        print(p, "parse fail", e); continue
    imgs = body.get('usedImages', [])
    names = [im.get('name','') for im in imgs]
    hit = [n for n in names if 'qmvcam' in n or 'vcameracrack' in n]
    print("==", os.path.basename(p), "异常:", body.get('exception'), " 相关镜像:", hit)
    if not hit: continue
    for t in body.get('threads', []):
        if t.get('triggered'):
            for f in t.get('frames', [])[:14]:
                idx = f.get('imageIndex', -1)
                nm = names[idx] if 0 <= idx < len(names) else '?'
                print("    %-28s +%s  %s" % (nm, f.get('imageOffset'), f.get('symbol','')))

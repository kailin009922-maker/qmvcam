#!/usr/bin/env python3
"""千面 VCam 激活码生成器（与重编译版的 vcam_license.m 对应）。

格式
----
    激活码 = base64url(payload) + "." + base64url(签名)
    payload = "QMV1|exp=<YYYYMMDD|0>|fp=<16位hex 或 *>|rnd=<8位hex>"

    签名算法：ECDSA P-256 / SHA-256（DER 编码，与 Security.framework 的
    kSecKeyAlgorithmECDSASignatureMessageX962SHA256 一致）

用法
----
    python keygen.py --fp 3f2a...c1 --days 365
    python keygen.py --fp 3f2a...c1 --exp 20271231
    python keygen.py --fp "*" --perm                # 不绑设备、永久
    python keygen.py --batch devices.txt --days 30  # 每行一个指纹

私钥默认读同目录 vcam_private_key.pem。
"""
import argparse, base64, datetime, os, secrets, sys
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes, serialization

HERE = os.path.dirname(os.path.abspath(__file__))

def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip('=')

def make_payload(fp: str, exp: str) -> bytes:
    rnd = secrets.token_hex(4)
    return f'QMV1|exp={exp}|fp={fp}|rnd={rnd}'.encode()

def sign(payload: bytes, key) -> str:
    sig = key.sign(payload, ec.ECDSA(hashes.SHA256()))
    return b64u(payload) + '.' + b64u(sig)

def load_key(path: str):
    with open(path, 'rb') as f:
        return serialization.load_pem_private_key(f.read(), password=None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fp', help='设备指纹（App 内“复制指纹”）或 * ')
    ap.add_argument('--exp', help='到期日 YYYYMMDD；0 表示永久')
    ap.add_argument('--days', type=int, help='从今天起 N 天')
    ap.add_argument('--perm', action='store_true', help='永久授权')
    ap.add_argument('--batch', help='批量：每行一个指纹')
    ap.add_argument('--key', default=os.path.join(HERE, 'vcam_private_key.pem'))
    a = ap.parse_args()

    if a.perm:
        exp = '0'
    elif a.exp:
        exp = a.exp
    elif a.days is not None:
        exp = (datetime.date.today() + datetime.timedelta(days=a.days)).strftime('%Y%m%d')
    else:
        exp = (datetime.date.today() + datetime.timedelta(days=365)).strftime('%Y%m%d')

    key = load_key(a.key)

    def one(fp):
        fp = fp.strip().lower()
        if fp != '*':
            fp = fp.replace(':', '').replace('-', '')
            if len(fp) not in (16, 32):
                print(f'[warn] 指纹长度异常（{len(fp)}）：{fp}', file=sys.stderr)
        payload = make_payload(fp, exp)
        code = sign(payload, key)
        print(f'{fp}\t{exp}\t{code}')
        return code

    if a.batch:
        for line in open(a.batch, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#'):
                one(line)
    elif a.fp:
        one(a.fp)
    else:
        ap.error('需要 --fp 或 --batch')

if __name__ == '__main__':
    main()

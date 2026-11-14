# 用内嵌公钥回验 keygen 生成的码（模拟 iOS 侧 SecKeyVerifySignature）
import base64, sys, subprocess
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes, serialization
pub = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), open("vcam_public_key.bin","rb").read())
line = subprocess.check_output([sys.executable, "keygen.py", "--fp", "3f2a9c81a0b4d7e6", "--perm"]).decode().strip()
fp, exp, code = line.split("\t")
p, s = code.split(".")
def d(x):
    x += "=" * (-len(x) % 4)
    return base64.urlsafe_b64decode(x)
payload, sig = d(p), d(s)
pub.verify(sig, payload, ec.ECDSA(hashes.SHA256()))
print("verify OK:", payload.decode())

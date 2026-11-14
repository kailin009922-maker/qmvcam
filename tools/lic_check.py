import base64, sys, datetime
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature
PUB = bytes.fromhex("0438e28dbad2673eeff255caf99fbc7de420991fa25649ecebcb2ddc248d5b365a839919ae65e5404bda1763f6cebe4070c343f320dddc9f09ac40ca6d0d131846")
p = r"D:\Backup\Documents\deepseek-harness\default-workspace\dev_pull\vc_license.txt"
code = open(p, encoding="utf-8").read().strip()
print("chars", len(code))
raw = base64.b64decode(code)
print("bytes", len(raw), "ver", raw[0], "siglen", raw[65], "expect", 66+raw[65])
print("fp", raw[1:17].hex())
exp = int.from_bytes(raw[17:21], "little"); mask = int.from_bytes(raw[21:25], "little")
print("exp", exp, datetime.datetime.fromtimestamp(exp, datetime.timezone.utc).isoformat() if exp else "permanent", "mask", mask)
try:
    ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), PUB).verify(raw[66:], raw[:65], ec.ECDSA(hashes.SHA256()))
    print("signature: OK (matches 556D key)")
except InvalidSignature:
    print("signature: FAIL")

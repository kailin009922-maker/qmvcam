from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization, hashes
import base64
key = ec.generate_private_key(ec.SECP256R1())
open("vcam_private_key.pem","wb").write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
pub = key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
open("vcam_public_key.bin","wb").write(pub)
print("pub hex:", pub.hex())
print("pub b64:", base64.b64encode(pub).decode())
sig = key.sign(b"hello", ec.ECDSA(hashes.SHA256()))
key.public_key().verify(sig, b"hello", ec.ECDSA(hashes.SHA256()))
print("sign/verify ok, DER sig len", len(sig))

import socket, sys
for port in (2222,):
    s = socket.socket(); s.settimeout(3)
    try:
        s.connect(("127.0.0.1", port))
        data = s.recv(64)
        print("banner:", data)
    except Exception as e:
        print("connect fail:", e)
    finally:
        s.close()

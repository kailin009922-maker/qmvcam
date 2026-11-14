import paramiko, sys
for user, pwd in (("root","alpine"), ("mobile","alpine")):
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        c.connect("127.0.0.1", port=2222, username=user, password=pwd, timeout=6, allow_agent=False, look_for_keys=False)
        print("OK", user)
        i,o,e = c.exec_command("uname -a; ls /Library/MobileSubstrate/DynamicLibraries 2>/dev/null | head")
        print(o.read().decode(errors="replace"))
        c.close(); break
    except Exception as ex:
        print("fail", user, type(ex).__name__, str(ex)[:120])

import json, os, subprocess, sys, threading

cmd = sys.argv[1:]
init = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": 1, "clientCapabilities": {}}}
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        env=os.environ.copy())
result = {}


def read():
    for line in proc.stdout:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == 1:
            result["msg"] = msg
            return


t = threading.Thread(target=read, daemon=True)
t.start()
proc.stdin.write((json.dumps(init) + "\n").encode())
proc.stdin.flush()
t.join(90)
proc.kill()
msg = result.get("msg")
if not msg or "result" not in msg:
    print("ACP 시험 실패:", msg)
    sys.exit(1)
info = msg["result"].get("agentInfo") or {}
print("ACP OK", msg["result"].get("protocolVersion"), info.get("name", ""), info.get("version", ""))

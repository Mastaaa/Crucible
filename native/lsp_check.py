#!/usr/bin/env python3
# GDScript warnings through Godot's language server (--check-only hides them).
# Usage (from the project folder): python3 native/lsp_check.py . scripts/game.gd tests/x.gd ...
# Prints "file line severity message" per diagnostic, then how many files it heard back on.
import json, socket, subprocess, sys, time, os
root = os.path.abspath(sys.argv[1]); files = sys.argv[2:]
p = subprocess.Popen(["godot", "--headless", "--editor", "--lsp-port", "6011", "--path", root],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
s = None
for _ in range(60):
    time.sleep(1)
    try:
        s = socket.create_connection(("127.0.0.1", 6011)); break
    except OSError: pass
def send(obj):
    b = json.dumps(obj).encode()
    s.sendall(b"Content-Length: %d\r\n\r\n" % len(b) + b)
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": None, "rootUri": "file://" + root, "capabilities": {}}})
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
for f in files:
    path = os.path.join(root, f)
    send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": "file://" + path, "languageId": "gdscript", "version": 1, "text": open(path).read()}}})
s.settimeout(1.0); buf = b""; diags = {}; end = time.time() + 20
while time.time() < end:
    try:
        d = s.recv(65536)
        if not d: break
        buf += d
    except socket.timeout: continue
    while b"\r\n\r\n" in buf:
        h, rest = buf.split(b"\r\n\r\n", 1)
        n = int([l for l in h.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
        if len(rest) < n: break
        msg = json.loads(rest[:n]); buf = rest[n:]
        if msg.get("method") == "textDocument/publishDiagnostics":
            diags[msg["params"]["uri"]] = msg["params"]["diagnostics"]
p.kill()
for uri, ds in diags.items():
    for d in ds:
        print(os.path.basename(uri), d["range"]["start"]["line"] + 1, d.get("severity"), d["message"])
print("checked", len(diags), "files")

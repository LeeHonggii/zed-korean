import subprocess, sys, pathlib
ours, base, out = map(pathlib.Path, sys.argv[1:4])
def changed(root):
    r = subprocess.run(["git", "status", "--porcelain", "-uall"], cwd=root, capture_output=True, text=True, check=True)
    files = []
    for line in r.stdout.splitlines():
        path = line[3:].strip('"')
        files.append(path)
    return files
skip = {"string_context.json", "Cargo.lock"}
paths = [p for p in changed(ours) if not p.startswith("HANDOFF") and p not in skip]
chunks, own = [], []
for p in paths:
    a, b = base / p, ours / p
    if a.exists() and b.exists() and a.read_bytes() == b.read_bytes():
        continue
    own.append(p)
    src = str(a) if a.exists() else "/dev/null"
    r = subprocess.run(["git", "diff", "--no-index", "--no-color", src, str(b)], capture_output=True, text=True)
    text = r.stdout.replace(f"a{a}", f"a/{p}").replace(f"b{b}", f"b/{p}").replace(f"a/{a}", f"a/{p}").replace(f"b/{b}", f"b/{p}")
    chunks.append(text)
out.write_text("".join(chunks))
print(len(paths), "changed /", len(own), "own")
for p in own: print(" ", p)

#!/usr/bin/env python3
"""Moves Crucible between Alex's PC and a cloud session as one archive each way.

On the PC (through the device shell), from anywhere:
  python3 <project>/native/sync.py pull           -> native/sync/pull.tgz (+ manifest.json)
  python3 <project>/native/sync.py apply [--force] <- native/sync/push.tgz
In the cloud container:
  python3 native/sync.py unpack <pull.tgz> [dir]   -> the project in dir (default /home/claude/crucible)
                                                      and an untouched copy beside it (<dir>.pristine)
  python3 native/sync.py pack [dir]                -> /mnt/user-data/outputs/push-<time>.tgz: every file
                                                      that differs from the pristine copy. Commit it with
                                                      device_commit_files to native/sync/push.tgz, then apply.
  python3 native/sync.py sent [dir]                after a good apply: the pristine copy takes the
                                                      files that went, so the next pack sends only newer ones
The staged file's name is new every time on purpose: a commit whose staged path was used
before sends the content first seen there, not what's there now.

`apply` refuses (and writes nothing) if any file it would overwrite changed on the PC since
the pull, unless --force. It writes the libraries first, so a Godot that has the DLL open
stops it before anything else is touched. Files are written in place (the PC shell can't
delete), and nothing is ever removed.
"""
import io
import json
import os
import sys
import tarfile
import time

SKIP_DIRS = {".godot", "native/godot-cpp", "native/sync"}
SKIP_FILES = {"native/.sconsign.dblite"}


def project_dir():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def walk(root):
    """Relative paths of the project's files, skipping build and editor output."""
    out = []
    for d, dirs, files in os.walk(root):
        rel = os.path.relpath(d, root).replace(os.sep, "/")
        rel = "" if rel == "." else rel
        dirs[:] = [x for x in dirs if (rel + "/" + x).lstrip("/") not in SKIP_DIRS]
        for f in files:
            p = (rel + "/" + f).lstrip("/")
            if p in SKIP_FILES or f.endswith((".exe", ".o", ".os", ".obj", ".tmp")):
                continue
            out.append(p)
    return sorted(out)


def lib_first(paths):
    return sorted(paths, key=lambda p: (not p.startswith("bin/"), p))


def pull():
    root = project_dir()
    sync = os.path.join(root, "native", "sync")
    os.makedirs(sync, exist_ok=True)
    files = walk(root)
    manifest = {p: os.stat(os.path.join(root, p)).st_mtime_ns for p in files}
    with open(os.path.join(sync, "manifest.json"), "w") as fh:
        json.dump(manifest, fh)
    tgz = os.path.join(sync, "pull.tgz")
    with tarfile.open(tgz, "w:gz") as tar:
        for p in files:
            tar.add(os.path.join(root, p), arcname=p)
    print("pulled %d files, %.1f MB -> native/sync/pull.tgz" % (len(files), os.path.getsize(tgz) / 1e6))


def apply(force):
    root = project_dir()
    sync = os.path.join(root, "native", "sync")
    with open(os.path.join(sync, "manifest.json")) as fh:
        manifest = json.load(fh)
    with tarfile.open(os.path.join(sync, "push.tgz"), "r:gz") as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        names = [m.name for m in members]
        if any(n.startswith("/") or ".." in n.split("/") for n in names):
            sys.exit("refused: bad path in push.tgz")
        changed = []
        for n in names:
            path = os.path.join(root, n)
            if n in manifest and os.path.exists(path) and os.stat(path).st_mtime_ns != manifest[n]:
                changed.append(n)
        if changed and not force:
            print("refused: changed on the PC since the pull (rerun with --force to overwrite):")
            for n in changed:
                print("  " + n)
            sys.exit(1)
        by_name = {m.name: m for m in members}
        done = 0
        for n in lib_first(names):
            data = tar.extractfile(by_name[n]).read()
            path = os.path.join(root, n)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            try:
                with open(path, "wb") as fh:
                    fh.write(data)
            except OSError as e:
                sys.exit("stopped at %s (%s): is Godot open? %d written before it" % (n, e.strerror, done))
            done += 1
            manifest[n] = os.stat(path).st_mtime_ns   # ours now: a later apply may overwrite it
    with open(os.path.join(sync, "manifest.json"), "w") as fh:
        json.dump(manifest, fh)
    print("applied %d files%s" % (done, " (forced over %d changed)" % len(changed) if changed else ""))


def unpack(tgz, dest):
    for d in (dest, dest + ".pristine"):
        os.makedirs(d, exist_ok=True)
        with tarfile.open(tgz, "r:gz") as tar:
            try:
                tar.extractall(d, filter="data")
            except TypeError:  # Python without extraction filters
                tar.extractall(d)
    print("unpacked %s into %s (and %s.pristine)" % (tgz, dest, dest))


def differing(src):
    base = src + ".pristine"
    if not os.path.isdir(base):
        sys.exit("no %s: unpack the pull into %s first" % (base, src))
    changed = []
    for p in walk(src):
        a = os.path.join(src, p)
        b = os.path.join(base, p)
        if not os.path.exists(b):
            # Godot's own bookkeeping for files it imported here; the PC makes its own.
            if p.endswith((".uid", ".import")) or p.startswith("native/docs/"):
                continue
        elif p.endswith(".import"):
            continue
        else:
            with open(a, "rb") as fa, open(b, "rb") as fb:
                if fa.read() == fb.read():
                    continue
        changed.append(p)
    return changed


def sent(src):
    import shutil
    changed = differing(src)
    for p in changed:
        dst = os.path.join(src + ".pristine", p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(src, p), dst)
    print("pristine copy updated with %d files" % len(changed))


def pack(src, out):
    changed = differing(src)
    if not changed:
        print("nothing changed")
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tarfile.open(out, "w:gz") as tar:
        for p in lib_first(changed):
            tar.add(os.path.join(src, p), arcname=p)
    print("packed %d files -> %s" % (len(changed), out))
    for p in lib_first(changed):
        print("  " + p)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "pull":
        pull()
    elif cmd == "apply":
        apply("--force" in a)
    elif cmd == "unpack":
        unpack(a[1], a[2] if len(a) > 2 else "/home/claude/crucible")
    elif cmd == "sent":
        sent(a[1] if len(a) > 1 else "/home/claude/crucible")
    elif cmd == "pack":
        out = a[2] if len(a) > 2 else "/mnt/user-data/outputs/push-%d.tgz" % int(time.time())
        pack(a[1] if len(a) > 1 else "/home/claude/crucible", out)
    else:
        sys.exit(__doc__)

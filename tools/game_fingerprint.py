"""Fingerprint every file inside the game's .pck (SHA-256 of each stored file).

The release builder uses this list to refuse any file that is byte-identical to a game file.
Only hashes are written - no game content. Usage: python game_fingerprint.py <pck> <out.json>
"""
import hashlib, json, struct, sys

pck_path, out_path = sys.argv[1], sys.argv[2]
with open(pck_path, "rb") as f:
    head = f.read(64)
    assert head[:4] == b"GDPC", "not a Godot pack"
    fmt, major, minor, patch = struct.unpack("<4I", head[4:20])
    flags, files_base = struct.unpack("<IQ", head[20:32])
    dir_offset, = struct.unpack("<Q", head[32:40])
    f.seek(dir_offset)
    count, = struct.unpack("<I", f.read(4))
    entries = []
    for _ in range(count):
        n, = struct.unpack("<I", f.read(4))
        path = f.read(n).rstrip(b"\0").decode()
        off, size = struct.unpack("<QQ", f.read(16))
        f.read(16)
        fl, = struct.unpack("<I", f.read(4))
        entries.append((path, off, size))
    hashes = {}
    for path, off, size in entries:
        f.seek(files_base + off)
        hashes[hashlib.sha256(f.read(size)).hexdigest()] = path
f2 = hashlib.sha256()
with open(pck_path, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        f2.update(chunk)
json.dump({"pck_sha256": f2.hexdigest(), "godot": f"{major}.{minor}.{patch}", "files": len(entries),
           "hashes": hashes}, open(out_path, "w"), indent=0)
print(f"{len(entries)} game files fingerprinted ({len(hashes)} unique) -> {out_path}")

"""Pack a custom minigame's own files into mods/<key>/<key>.zip (mod-src/ in the author's workspace).

Only files under <project>/custom_minigames_content/<key>/ are packed (our work). <project> is the
private recovered Godot project ("decompiled") when present, else the public repo's "content" folder.
Editor side-files (.uid, .import) and anything else are skipped. Paths inside the zip
keep their res:// layout so the mod loader can mount the zip as a resource pack.
Usage: python build_pack.py <key> [MachineParty-Mod folder]
"""
import os, sys, zipfile, hashlib

key = sys.argv[1]
root = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
project = os.path.join(root, "decompiled")
if not os.path.isdir(os.path.join(project, "custom_minigames_content")):
    project = os.path.join(root, "content")      # layout of the public source repo
content = os.path.join(project, "custom_minigames_content", key)
mods = os.path.join(root, "mod-src") if os.path.isdir(os.path.join(root, "mod-src")) else os.path.join(root, "mods")
out = os.path.join(mods, key, key + ".zip")
ALLOWED = (".gd", ".tscn", ".tres")
if not os.path.isdir(content):
    sys.exit(f"no content folder: {content}")
files = []
for dirpath, _, names in os.walk(content):
    for n in sorted(names):
        if n.endswith(ALLOWED):
            files.append(os.path.join(dirpath, n))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(files):
        arc = os.path.relpath(f, project).replace(os.sep, "/")
        z.write(f, arc)
        print("packed", arc)
print("wrote", out, hashlib.sha256(open(out, "rb").read()).hexdigest())

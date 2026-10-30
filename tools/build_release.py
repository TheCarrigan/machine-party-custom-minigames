"""Build a release of Custom Minigames (+ Live Wire, Power Grid, Spotlight) and check that it contains only our own work.

Steps: repack each minigame's content -> copy the release mods and docs into release/<name>/ -> run checks
-> zip. The build FAILS (no zip) if any check fails:
  1. only expected file types are present (code, mod manifests, settings, docs, our icon, our pack)
  2. each minigame pack contains only files under custom_minigames_content/
  3. no file (or file inside the pack) is byte-identical to any file inside the game (game_file_hashes.json)
  4. no copied block of game code: 3+ consecutive substantial lines that also appear in the game's
     decompiled scripts (single matching lines - e.g. a function signature we must repeat to wrap it -
     are listed for information only)
Usage: python build_release.py <MachineParty-Mod folder>
"""
import hashlib, json, os, re, shutil, subprocess, sys, zipfile

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
# works in the public repo (mods/, docs/) and in the author's workspace (mod-src/, release-docs/)
SRC = os.path.join(ROOT, "mod-src") if os.path.isdir(os.path.join(ROOT, "mod-src")) else os.path.join(ROOT, "mods")
DOCS = os.path.join(ROOT, "release-docs") if os.path.isdir(os.path.join(ROOT, "release-docs")) else os.path.join(ROOT, "docs")
RELEASE_MODS = ["custom_minigames", "live_wire", "power_grid", "spotlight"]
MINIGAMES = [("live_wire", "livewire"), ("power_grid", "powergrid"), ("spotlight", "spotlight")]   # (mod folder, short name in the release name)
SKIP_FILES = {"SIMULATE_GAME_UPDATE"}
ALLOWED_EXT = {".gd", ".json", ".cfg", ".zip", ".png", ".md", ".txt", ".bat", ".ps1", ""}
INSTALLER = os.path.join(ROOT, "installer")   # Install.bat, Uninstall.bat, installer.ps1
PACK_EXT = {".gd", ".tscn", ".tres"}

def sha(b): return hashlib.sha256(b).hexdigest()

def version():
    v = lambda m: json.load(open(os.path.join(SRC, m, "mod.json")))["version"]
    return v("custom_minigames") + "".join(f"-{short}-{v(m)}" for m, short in MINIGAMES)

def norm(line):
    return re.sub(r"\s+", " ", line.strip())

def substantial(line):
    l = norm(line)
    return len(l) >= 25 and not l.startswith("#") and not l.startswith("extends ") and not l.startswith("func ")

def game_corpus():
    lines = set()
    for d, _, fs in os.walk(os.path.join(ROOT, "decompiled-scripts")):
        for f in fs:
            if f.endswith(".gd"):
                for l in open(os.path.join(d, f), encoding="utf-8", errors="replace"):
                    if substantial(l):
                        lines.add(norm(l))
    return lines

def code_matches(name, text, corpus):
    rows = text.splitlines()
    single, blocks, run = [], [], []
    for i, l in enumerate(rows, 1):
        if substantial(l) and norm(l) in corpus:
            single.append((i, norm(l)))
            run.append((i, norm(l)))
        elif l.strip() == "" or l.strip().startswith("#"):
            continue   # blank lines/comments don't break a copied block
        else:
            if len(run) >= 3: blocks.append(list(run))
            run = []
    if len(run) >= 3: blocks.append(list(run))
    return single, blocks

def main():
    ver = version()
    name = f"custom-minigames-{ver}"
    out_dir = os.path.join(ROOT, "release", name)
    print(f"== building {name}")
    for m, _ in MINIGAMES:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_pack.py"), m, ROOT], check=True)
    if os.path.exists(out_dir):
        n = 1
        while os.path.exists(f"{out_dir}-old{n}"): n += 1
        os.rename(out_dir, f"{out_dir}-old{n}")   # deleting isn't always allowed; keep the old one aside
    for m in RELEASE_MODS:
        dst = os.path.join(out_dir, "mods", m)
        for d, _, fs in os.walk(os.path.join(SRC, m)):
            for f in fs:
                if f in SKIP_FILES: continue
                rel = os.path.relpath(os.path.join(d, f), os.path.join(SRC, m))
                os.makedirs(os.path.join(dst, os.path.dirname(rel)), exist_ok=True)
                shutil.copy2(os.path.join(d, f), os.path.join(dst, rel))
    for f in os.listdir(DOCS):
        shutil.copy2(os.path.join(DOCS, f), os.path.join(out_dir, f))
    if not os.path.exists(os.path.join(out_dir, "LICENSE")):
        shutil.copy2(os.path.join(ROOT, "LICENSE"), os.path.join(out_dir, "LICENSE"))
    os.makedirs(os.path.join(out_dir, "installer"), exist_ok=True)
    for f in ("Install.bat", "Uninstall.bat"):
        shutil.copy2(os.path.join(INSTALLER, f), os.path.join(out_dir, f))
    shutil.copy2(os.path.join(INSTALLER, "installer.ps1"), os.path.join(out_dir, "installer", "installer.ps1"))

    problems, info = [], []
    game = json.load(open(os.path.join(ROOT, "tools", "game_file_hashes.json")))["hashes"]
    corpus = game_corpus()
    def check_text(label, text):
        single, blocks = code_matches(label, text, corpus)
        for i, l in single: info.append(f"   {label}:{i} also in game: {l[:90]}")
        for b in blocks:
            problems.append(f"copied block in {label} lines {b[0][0]}-{b[-1][0]}:\n      " + "\n      ".join(l[:100] for _, l in b))
    files = []
    for d, _, fs in os.walk(out_dir):
        for f in fs:
            files.append(os.path.join(d, f))
    for p in sorted(files):
        rel = os.path.relpath(p, out_dir).replace(os.sep, "/")
        data = open(p, "rb").read()
        ext = os.path.splitext(p)[1].lower()
        if ext not in ALLOWED_EXT:
            problems.append(f"unexpected file type: {rel}")
        if sha(data) in game:
            problems.append(f"{rel} is identical to game file {game[sha(data)]}")
        if ext == ".gd":
            check_text(rel, data.decode("utf-8", "replace"))
        if ext == ".zip":
            with zipfile.ZipFile(p) as z:
                for zi in z.namelist():
                    zdata = z.read(zi)
                    if not zi.startswith("custom_minigames_content/"):
                        problems.append(f"{rel} contains a file outside our folder: {zi}")
                    if os.path.splitext(zi)[1] not in PACK_EXT:
                        problems.append(f"{rel} contains unexpected type: {zi}")
                    if sha(zdata) in game:
                        problems.append(f"{rel}:{zi} is identical to game file {game[sha(zdata)]}")
                    if zi.endswith(".gd"):
                        check_text(f"{rel}:{zi}", zdata.decode("utf-8", "replace"))
    print(f"== {len(files)} files checked against {len(game)} game files and {len(corpus)} game code lines")
    if info:
        print("== single lines shared with the game (signatures/API calls we must match; informational):")
        print("\n".join(info))
    if problems:
        print("== BUILD FAILED:")
        for pr in problems: print(" - " + pr)
        sys.exit(1)
    zpath = os.path.join(ROOT, "release", name + ".zip")
    if os.path.exists(zpath):
        n = 1
        while os.path.exists(f"{zpath[:-4]}-old{n}.zip"): n += 1
        os.rename(zpath, f"{zpath[:-4]}-old{n}.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(files):
            z.write(p, os.path.join(name, os.path.relpath(p, out_dir)))
    print(f"== OK: {zpath}\n   sha256 {sha(open(zpath,'rb').read())}")

if __name__ == "__main__":
    main()

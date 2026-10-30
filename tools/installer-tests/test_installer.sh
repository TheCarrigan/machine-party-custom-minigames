#!/bin/bash
# Tests installer/installer.ps1 with PowerShell 7 (pwsh) on a fake game folder and fake Steam library.
# Usage: PWSH=/path/to/pwsh bash test_installer.sh <MachineParty-Mod folder>
M="${1:-$HOME/mnt/MachineParty-Mod}"; PW="${PWSH:-pwsh}"; T="$(mktemp -d)"; fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
R="$T/release"; mkdir -p "$R/installer"; cp "$M/installer/installer.ps1" "$R/installer/"
for m in custom_minigames live_wire power_grid; do mkdir -p "$R/mods/$m"; echo "{\"id\":\"$m\",\"version\":\"9.9.9\"}" > "$R/mods/$m/mod.json"; done
printf '[practice]\n; how many bots\nbots=0\nnew_option=1\n' > "$R/mods/live_wire/settings.cfg"
G="$T/game dir"; mkdir -p "$G"; touch "$G/Machine Party.exe" "$G/Machine Party.pck"
run() { "$PW" -NoProfile -File "$R/installer/installer.ps1" "$@" > "$T/out.txt" 2>&1; echo $?; }
check "refuses without the mod loader" '[ "$(run -Mode install -GameDir "$G" -Yes)" = 1 ] && [ ! -d "$G/mods" ]'
touch "$G/Machine Party.pck.modloader.json"; mkdir -p "$G/mods/console" "$G/mods/live_wire"; echo keep > "$G/mods/console/x"
printf '[practice]\nbots=3\n' > "$G/mods/live_wire/settings.cfg"; echo stale > "$G/mods/live_wire/old_file.gd"
check "installs/updates" '[ "$(run -Mode install -GameDir "$G" -Yes)" = 0 ] && [ -f "$G/mods/power_grid/mod.json" ]'
check "keeps the player's settings" 'grep -q "^bots=3" "$G/mods/live_wire/settings.cfg"'
check "adds new settings" 'grep -q "^new_option=1" "$G/mods/live_wire/settings.cfg"'
check "removes stale files" '[ ! -f "$G/mods/live_wire/old_file.gd" ]'
check "leaves other mods alone" '[ "$(cat "$G/mods/console/x")" = keep ]'
check "rejects a wrong folder" '[ "$(run -Mode install -GameDir "$T/nope" -Yes)" = 1 ]'
ST="$T/Steam"; L2="$T/OtherLib"; G2="$L2/steamapps/common/party project/Machine Party_Windows"
mkdir -p "$ST/steamapps" "$G2/mods"; touch "$G2/Machine Party.exe" "$G2/Machine Party.pck" "$G2/Machine Party.pck.modloader.json"
printf '"libraryfolders"\n{\n "0" { "path" "%s" }\n "1" { "path" "%s" }\n}\n' "$ST" "$L2" > "$ST/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n "appid" "4108000"\n "installdir" "party project"\n}\n' > "$L2/steamapps/appmanifest_4108000.acf"
check "finds the game through Steam's library list" '[ "$(run -Mode install -Yes -SteamPath "$ST")" = 0 ] && [ -d "$G2/mods/live_wire" ]'
cp -r "$R" "$G/custom-minigames-x"
check "works when unzipped inside the game folder" '"$PW" -NoProfile -File "$G/custom-minigames-x/installer/installer.ps1" -Mode install -Yes > /dev/null 2>&1'
check "uninstall removes only our folders" '[ "$(run -Mode uninstall -GameDir "$G" -Yes)" = 0 ] && [ ! -d "$G/mods/live_wire" ] && [ -d "$G/mods/console" ]'
check "uninstall twice is harmless" '[ "$(run -Mode uninstall -GameDir "$G" -Yes)" = 0 ]'
rm -rf "$T"; [ $fail = 0 ] && echo "INSTALLER: ALL OK" || echo "INSTALLER: FAILED"; exit $fail

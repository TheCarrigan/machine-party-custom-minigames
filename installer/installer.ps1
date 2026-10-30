# Custom Minigames for Machine Party - installer / uninstaller (unofficial fan mod).
# Plain PowerShell, no downloads, nothing hidden. It only ever creates, replaces or removes these
# folders inside the game's "mods" folder: custom_minigames, live_wire, power_grid.
# It never touches your saves or settings in %APPDATA%, the game files, or the mod loader.
#
# Usage (the .bat files do this for you):
#   installer.ps1 -Mode install   [-GameDir "<folder with Machine Party.exe>"] [-Yes]
#   installer.ps1 -Mode uninstall [-GameDir "..."] [-Yes]
param(
    [ValidateSet("install", "uninstall")][string]$Mode = "install",
    [string]$GameDir = "",
    [switch]$Yes,
    [string]$SourceDir = "",
    [string]$SteamPath = ""     # for testing; normally read from the registry
)
$ErrorActionPreference = "Stop"
$ModFolders = @("custom_minigames", "live_wire", "power_grid")
$LoaderUrl = "https://github.com/Krunk-theduck/MachinePartyModLoader"
$Exe = "Machine Party.exe"
$Pck = "Machine Party.pck"
if ($SourceDir -eq "") { $SourceDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
# the mod folders are the ones that came in this download's "mods" folder
$inDownload = @(Get-ChildItem -LiteralPath (Join-Path $SourceDir "mods") -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
if ($inDownload.Count -gt 0) { $ModFolders = $inDownload }

function Say([string]$text) { Write-Host $text }
function Stop-With([string]$text) { Write-Host ""; Write-Host "STOPPED: $text" -ForegroundColor Yellow; exit 1 }
function Ask-YesNo([string]$question) {
    if ($Yes) { return $true }
    $a = Read-Host "$question [y/N]"
    return ($a -match '^(y|yes)$')
}
function Is-GameDir([string]$dir) {
    return ($dir -ne "") -and (Test-Path -LiteralPath (Join-Path $dir $Exe)) -and (Test-Path -LiteralPath (Join-Path $dir $Pck))
}

# --- 1. find the game folder ---------------------------------------------------------------
function Find-SteamGameDirs {
    $found = @()
    $steam = $SteamPath
    if ($steam -eq "") {
        try { $steam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch { }
    }
    if (-not $steam) { return $found }
    $libs = @($steam)
    $vdf = Join-Path (Join-Path $steam "steamapps") "libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $apps = Join-Path $lib "steamapps"
        $manifest = Join-Path $apps "appmanifest_4108000.acf"     # Machine Party's Steam app id
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $m = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"')
        if (-not $m.Success) { continue }
        $root = Join-Path (Join-Path $apps "common") $m.Groups[1].Value
        foreach ($d in @($root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) {
            if (Is-GameDir $d) { $found += $d }
        }
    }
    return $found
}

function Resolve-GameDir {
    if ($GameDir -ne "") {
        if (Is-GameDir $GameDir) { return (Resolve-Path -LiteralPath $GameDir).Path }
        Stop-With "No '$Exe' and '$Pck' in: $GameDir"
    }
    $parent = Split-Path -Parent $SourceDir
    if (Is-GameDir $parent) { return $parent }         # the download was unpacked inside the game folder
    $candidates = @(Find-SteamGameDirs)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        Say "Found more than one Machine Party folder:"
        for ($i = 0; $i -lt $candidates.Count; $i++) { Say ("  {0}) {1}" -f ($i + 1), $candidates[$i]) }
        $n = Read-Host "Type the number to use"
        $k = 0
        if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $candidates.Count) { return $candidates[$k - 1] }
        Stop-With "No folder chosen."
    }
    if ($Yes) { Stop-With "Couldn't find the game. Run again with -GameDir." }
    Say "Couldn't find Machine Party through Steam."
    Say "In Steam: right-click Machine Party > Manage > Browse local files, open 'Machine Party_Windows',"
    Say "then copy the folder path from the address bar."
    $p = (Read-Host "Paste the folder path here").Trim('"', ' ')
    if (Is-GameDir $p) { return (Resolve-Path -LiteralPath $p).Path }
    Stop-With "No '$Exe' and '$Pck' in: $p"
}

# --- 2. settings: keep the player's values, add any new options ------------------------------
function Read-Ini([string]$text) {
    $data = [ordered]@{}; $section = ""
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
        if ($t -match '^([^;#=][^=]*?)\s*=\s*(.*)$') { $data["$section|$($Matches[1])"] = $Matches[2] }
    }
    return $data
}
function Merge-Settings([string]$newText, [string]$oldText) {
    $old = Read-Ini $oldText; $section = ""; $out = @()
    foreach ($line in ($newText -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $section = $Matches[1]; $out += $line; continue }
        if ($t -match '^([^;#=][^=]*?)\s*=\s*(.*)$') {
            $key = "$section|$($Matches[1])"
            if ($old.Contains($key)) { $out += ("{0}={1}" -f $Matches[1], $old[$key]); continue }
        }
        $out += $line
    }
    return ($out -join "`r`n")
}

# --- main ----------------------------------------------------------------------------------
Say "Custom Minigames for Machine Party - $Mode"
Say ("(Unofficial fan mod. Only touches these folders in the game's mods folder: " + ($ModFolders -join ", ") + ")")
Say ""
$game = Resolve-GameDir
Say "Game folder: $game"
if (Get-Process -Name "Machine Party" -ErrorAction SilentlyContinue) { Stop-With "Machine Party is running. Close it, then run this again." }
$mods = Join-Path $game "mods"

if ($Mode -eq "uninstall") {
    $present = @($ModFolders | Where-Object { Test-Path -LiteralPath (Join-Path $mods $_) })
    if ($present.Count -eq 0) { Say "Nothing to remove: the mod isn't installed here."; exit 0 }
    Say ("Will delete: " + (($present | ForEach-Object { "mods\$_" }) -join ", "))
    if (-not (Ask-YesNo "Remove the mod?")) { Stop-With "Nothing changed." }
    foreach ($f in $present) { Remove-Item -LiteralPath (Join-Path $mods $f) -Recurse -Force }
    Say ""
    Say "Removed. The mod loader and any other mods are still installed."
    Say "To remove the mod loader too: Steam > Machine Party > Properties > Installed Files >"
    Say "Verify integrity of game files."
    exit 0
}

# install
$patched = (Test-Path -LiteralPath (Join-Path $game "$Pck.modloader.json")) -and (Test-Path -LiteralPath $mods)
if (-not $patched) {
    Say ""
    Say "The Machine Party Mod Loader isn't installed in this game folder yet. This mod needs it."
    Say "  1. Download it from: $LoaderUrl"
    Say "  2. Put MachinePartyModLoader.exe next to '$Exe' and run it once."
    Say "  3. Run this installer again."
    if (-not $Yes -and (Ask-YesNo "Open the mod loader's page in your browser now?")) { Start-Process $LoaderUrl }
    Stop-With "Mod loader needed first."
}
foreach ($f in $ModFolders) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $SourceDir "mods") $f))) { Stop-With "This download is incomplete: mods\$f is missing. Unzip the whole download first." }
}
$existing = @($ModFolders | Where-Object { Test-Path -LiteralPath (Join-Path $mods $_) })
if ($existing.Count -gt 0) { Say "Updating an existing install (your settings.cfg choices are kept)." }
if (-not (Ask-YesNo "Install into this game folder?")) { Stop-With "Nothing changed." }

foreach ($f in $ModFolders) {
    $src = Join-Path (Join-Path $SourceDir "mods") $f
    $dst = Join-Path $mods $f
    if ((Resolve-Path -LiteralPath $src).Path -eq [IO.Path]::GetFullPath($dst)) { Stop-With "The download is already in place (mods\$f). Nothing to copy." }
    $oldSettings = $null
    $settingsPath = Join-Path $dst "settings.cfg"
    if (Test-Path -LiteralPath $settingsPath) { $oldSettings = Get-Content -LiteralPath $settingsPath -Raw }
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }   # no stale files from older versions
    Copy-Item -LiteralPath $src -Destination $dst -Recurse
    if ($null -ne $oldSettings -and (Test-Path -LiteralPath $settingsPath)) {
        $merged = Merge-Settings (Get-Content -LiteralPath $settingsPath -Raw) $oldSettings
        Set-Content -LiteralPath $settingsPath -Value $merged -NoNewline -Encoding ASCII
    }
    $ver = "?"
    try { $ver = (Get-Content -LiteralPath (Join-Path $dst "mod.json") -Raw | ConvertFrom-Json).version } catch { }
    Say ("  installed mods\{0} ({1})" -f $f, $ver)
}
Say ""
Say "Done. Start the game through Steam. Everyone in your lobby needs this same version."
Say "To practise alone: open mods\live_wire\settings.cfg or mods\power_grid\settings.cfg in Notepad and set bots=3."
exit 0

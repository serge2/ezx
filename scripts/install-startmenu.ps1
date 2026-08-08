# Adds an "ezx" shortcut to the current user's Start menu.
# Run from an unpacked release: bin\install-startmenu.ps1
# (from cmd: powershell -ExecutionPolicy Bypass -File bin\install-startmenu.ps1)
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vbs = Join-Path $root 'bin\ezx-launch.vbs'
if (-not (Test-Path $vbs)) {
    Write-Error "ezx-launch.vbs not found next to this script ($vbs) — run from an unpacked release"
    exit 1
}
$icon = Get-ChildItem -Path $root -Recurse -Filter ezx.ico -ErrorAction SilentlyContinue | Select-Object -First 1
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
if (-not (Test-Path $menu)) { New-Item -ItemType Directory -Path $menu | Out-Null }
$lnk = Join-Path $menu 'ezx.lnk'
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$sc.Arguments = '"' + $vbs + '"'
if ($icon) { $sc.IconLocation = $icon.FullName + ',0' }
$sc.WorkingDirectory = $root
$sc.Description = 'ezx ZX Spectrum emulator'
$sc.Save()
Write-Host "Start menu shortcut created: $lnk"

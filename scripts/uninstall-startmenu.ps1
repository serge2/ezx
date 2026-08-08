# Removes the "ezx" Start menu shortcut created by install-startmenu.ps1.
# Idempotent: nothing to remove is not an error.
param()
$ErrorActionPreference = 'Stop'
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$lnk = Join-Path $menu 'ezx.lnk'
if (Test-Path $lnk) {
    Remove-Item $lnk -Force
    Write-Host "Start menu shortcut removed: $lnk"
} else {
    Write-Host "No Start menu shortcut at $lnk"
}

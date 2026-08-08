; ezx Windows installer (NSIS 3).
;
; Build from the repo root (after the prod release exists), e.g. on Windows:
;   makensis -DVERSION=1.2.0 -DRELDIR="_build\prod\rel\ezx\*" packaging/ezx.nsi
; (on Unix pass a forward-slash mask: -DRELDIR="_build/prod/rel/ezx/*").
;
; Installs per-user into %LOCALAPPDATA%\Programs\ezx (no administrator
; rights), creates Start menu + desktop shortcuts to bin\ezx-launch.vbs with
; the app icon, registers an Add/Remove Programs entry in HKCU and ships a
; self-removing Uninstall.exe. User data (settings, saves) lives in the app's
; own %LOCALAPPDATA%\ezx dirs and is deliberately left untouched.
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef RELDIR
  !error "RELDIR (the built release as a file mask, e.g. _build\prod\rel\ezx\*) must be passed with -DRELDIR=..."
!endif
!ifndef OUTFILE
  !define OUTFILE "dist/ezx-setup-${VERSION}.exe"
!endif

Unicode true
Name "ezx ZX Spectrum emulator"
!define PUBLISHER "ezx"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\ezx"
InstallDirRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma

!define MUI_ICON "../priv/ezx.ico"
!define MUI_UNICON "../priv/ezx.ico"
!define MUI_ABORTWARNING
; The finish-page checkbox runs the target via `Exec`, which only spawns real
; executables — a bare .vbs silently does nothing. Launch wscript.exe with the
; vbs as its argument, exactly like the desktop/Start menu shortcuts.
!define MUI_FINISHPAGE_RUN "$WINDIR\System32\wscript.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ezx now"
!define MUI_FINISHPAGE_RUN_PARAMETERS '"$INSTDIR\bin\ezx-launch.vbs"'

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "ezx ZX Spectrum emulator"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "ezx ZX Spectrum emulator"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 Sergii Polkovnikov <serge.polkovnikov@gmail.com>"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

Section "Install" SecInstall
  SetOutPath "$INSTDIR"
  File /r "${RELDIR}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\ezx"
  CreateShortCut "$SMPROGRAMS\ezx\ezx.lnk" "$WINDIR\System32\wscript.exe" \
      '"$INSTDIR\bin\ezx-launch.vbs"' "$INSTDIR\lib\ezx-${VERSION}\priv\ezx.ico" 0 SW_SHOWNORMAL "" "ezx ZX Spectrum emulator"
  CreateShortCut "$DESKTOP\ezx.lnk" "$WINDIR\System32\wscript.exe" \
      '"$INSTDIR\bin\ezx-launch.vbs"' "$INSTDIR\lib\ezx-${VERSION}\priv\ezx.ico" 0 SW_SHOWNORMAL "" "ezx ZX Spectrum emulator"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "DisplayName" "ezx ZX Spectrum emulator"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "DisplayIcon" "$INSTDIR\lib\ezx-${VERSION}\priv\ezx.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "EstimatedSize" $0
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx" "InstallDate" "${__DATE__}"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\ezx\ezx.lnk"
  RMDir "$SMPROGRAMS\ezx"
  Delete "$DESKTOP\ezx.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ezx"
SectionEnd

@echo off
rem Desktop launcher for the ezx release (Windows equivalent of ezx-launch).
rem Boots the VM WITHOUT a node name (nonode@nohost) straight into the app,
rem bypassing the bin\ezx.cmd release-management CLI (on Windows "start"
rem means an erlsrv Windows service and is not how a GUI app runs).
rem
rem The release root is resolved from this script's own location, so it works
rem wherever the zip is unpacked.
setlocal
for %%i in ("%~dp0..") do set "ROOT=%%~fi"
for /f "usebackq tokens=1,2" %%a in ("%ROOT%\releases\start_erl.data") do (
  set "ERTS_VSN=%%a"
  set "REL_VSN=%%b"
)
if "%REL_VSN%"=="" (
  echo ezx-launch: cannot read "%ROOT%\releases\start_erl.data" 1>&2
  exit /b 1
)
set "ROOTDIR=%ROOT%"
set "RELEASE_ROOT_DIR=%ROOT%"
set "BINDIR=%ROOT%\erts-%ERTS_VSN%\bin"
set "EMU=beam"
set "PROGNAME=erl"
"%BINDIR%\erl.exe" -noinput +Bd +K true -boot "%ROOT%\releases\%REL_VSN%\start" -mode embedded -boot_var SYSTEM_LIB_DIR "%ROOT%\lib" -config "%ROOT%\releases\%REL_VSN%\sys.config" %*
exit /b %errorlevel%

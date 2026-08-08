' Double-click launcher for ezx (Windows): runs bin\ezx-launch.cmd with no
' console window, so only the emulator window appears.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run """" & dir & "\ezx-launch.cmd" & """", 0, False

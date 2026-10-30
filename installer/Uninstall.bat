@echo off
rem Removes the Custom Minigames mod folders. Read installer\installer.ps1 to see exactly what it does.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\installer.ps1" -Mode uninstall %*
pause

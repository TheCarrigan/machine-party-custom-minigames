@echo off
rem Installs the Custom Minigames mod. Read installer\installer.ps1 to see exactly what it does.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\installer.ps1" -Mode install %*
pause

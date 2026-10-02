@echo off
pwsh.exe -NoProfile -File "%~dp0SoundRecorder.ps1" %*
if errorlevel 1 pause

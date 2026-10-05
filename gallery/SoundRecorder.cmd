@echo off
pwsh.exe -NoProfile -File "%~dp0SoundRecorder.ps1" %*
exit /b %ERRORLEVEL%

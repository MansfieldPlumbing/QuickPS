@echo off
pwsh.exe -NoProfile -File "%~dp0WindowCapture.ps1" %*
exit /b %ERRORLEVEL%

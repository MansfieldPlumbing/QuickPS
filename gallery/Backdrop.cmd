@echo off
pwsh.exe -NoProfile -File "%~dp0Backdrop.ps1" %*
exit /b %ERRORLEVEL%

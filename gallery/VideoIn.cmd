@echo off
pwsh.exe -NoProfile -File "%~dp0VideoIn.ps1" %*
exit /b %ERRORLEVEL%

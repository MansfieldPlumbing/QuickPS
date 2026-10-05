@echo off
pwsh.exe -NoProfile -File "%~dp0Debugger.ps1" %*
exit /b %ERRORLEVEL%

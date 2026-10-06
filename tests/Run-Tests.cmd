@echo off
pwsh.exe -NoProfile -File "%~dp0Run-Tests.ps1" %*
exit /b %ERRORLEVEL%

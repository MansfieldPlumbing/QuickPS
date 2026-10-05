@echo off
pwsh.exe -NoProfile -File "%~dp0Typography.ps1" %*
exit /b %ERRORLEVEL%

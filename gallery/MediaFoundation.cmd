@echo off
pwsh.exe -NoProfile -File "%~dp0MediaFoundation.ps1" %*
exit /b %ERRORLEVEL%

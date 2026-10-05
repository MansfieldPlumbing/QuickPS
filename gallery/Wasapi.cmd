@echo off
pwsh.exe -NoProfile -File "%~dp0Wasapi.ps1" %*
exit /b %ERRORLEVEL%

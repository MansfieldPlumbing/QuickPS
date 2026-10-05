@echo off
pwsh.exe -NoProfile -File "%~dp0Native.ps1" %*
exit /b %ERRORLEVEL%

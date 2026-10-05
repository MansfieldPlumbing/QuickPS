@echo off
pwsh.exe -NoProfile -File "%~dp0DXGI.ps1" %*
exit /b %ERRORLEVEL%

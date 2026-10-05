@echo off
pwsh.exe -NoProfile -File "%~dp0WindowControls.ps1" %*
exit /b %ERRORLEVEL%

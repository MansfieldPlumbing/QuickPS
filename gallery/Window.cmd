@echo off
pwsh.exe -NoProfile -File "%~dp0Window.ps1" %*
exit /b %ERRORLEVEL%

@echo off
pwsh.exe -NoProfile -File "%~dp0Wic.ps1" %*
exit /b %ERRORLEVEL%

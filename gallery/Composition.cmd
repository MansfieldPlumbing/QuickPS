@echo off
pwsh.exe -NoProfile -File "%~dp0Composition.ps1" %*
exit /b %ERRORLEVEL%

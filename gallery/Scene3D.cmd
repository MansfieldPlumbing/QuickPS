@echo off
pwsh.exe -NoProfile -File "%~dp0Scene3D.ps1" %*
exit /b %ERRORLEVEL%

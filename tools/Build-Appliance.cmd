@echo off
pwsh.exe -NoProfile -File "%~dp0Build-Appliance.ps1" %*
exit /b %ERRORLEVEL%

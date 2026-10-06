@echo off
pwsh.exe -NoProfile -File "%~dp0Acquire-PSLowering.ps1" %*
exit /b %ERRORLEVEL%

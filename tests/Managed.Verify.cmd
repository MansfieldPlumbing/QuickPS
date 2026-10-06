@echo off
pwsh.exe -NoProfile -File "%~dp0Managed.Verify.ps1" %*
exit /b %ERRORLEVEL%

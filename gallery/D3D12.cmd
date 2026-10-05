@echo off
pwsh.exe -NoProfile -File "%~dp0D3D12.ps1" %*
exit /b %ERRORLEVEL%

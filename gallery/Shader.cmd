@echo off
pwsh.exe -NoProfile -File "%~dp0Shader.ps1" %*
exit /b %ERRORLEVEL%

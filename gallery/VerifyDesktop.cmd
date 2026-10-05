@echo off
pwsh.exe -NoProfile -File "%~dp0WindowControls.ps1" -Verify -AppScript "%~dp0apps\Files.ps1"
if errorlevel 1 goto done
pwsh.exe -NoProfile -File "%~dp0Backdrop.ps1" -Verify
:done
pause

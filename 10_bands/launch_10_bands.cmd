@echo off
setlocal
set PS1=%%~dp0launch_10_bands.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ""%%PS1%%"" -Fullscreen
endlocal

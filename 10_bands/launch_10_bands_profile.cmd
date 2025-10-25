@echo off
REM launch_10_bands_profile.cmd - Quick launcher using Windows Terminal profile

REM Launch using WT profile (fastest method)
wt -p "10_Bands" --fullscreen

if %ERRORLEVEL% NEQ 0 (
    echo Failed to launch Windows Terminal profile.
    echo.
    echo Run setup first: setup_profile.cmd
    echo.
    pause
    exit /b 1
)

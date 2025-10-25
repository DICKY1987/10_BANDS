@echo off
REM setup_profile.cmd - One-time setup for 10_Bands Windows Terminal profile

echo ========================================
echo 10_Bands Profile Setup
echo ========================================
echo.
echo This will:
echo   1. Create/update Windows Terminal profile
echo   2. Create desktop shortcut (optional)
echo   3. Launch the layout (optional)
echo.

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_profile.ps1" -CreateShortcut -LaunchAfterSetup

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Setup failed! Check the error messages above.
    pause
    exit /b 1
)

echo.
echo Setup complete! Press any key to exit...
pause >nul

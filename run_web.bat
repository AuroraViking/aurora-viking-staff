@echo off
echo.
echo ========================================
echo   Aurora Viking Staff - Web Runner
echo ========================================
echo.
echo Running PowerShell script...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0run_web.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo Script failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)

pause

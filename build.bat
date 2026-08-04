@echo off
rem MaxScatter -- builds dist\MaxScatter.mzp from src\
rem The exit code is propagated: a build that died halfway used to leave a
rem broken .mzp in dist\ and still look like it had succeeded.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\build_mzp.ps1"
if errorlevel 1 (
    echo.
    echo BUILD FAILED -- dist\MaxScatter.mzp is NOT usable.
    exit /b 1
)
exit /b 0

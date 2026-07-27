@echo off
rem MaxScatter -- builds dist\MaxScatter-v<version>.mzp from src\
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\build_mzp.ps1"

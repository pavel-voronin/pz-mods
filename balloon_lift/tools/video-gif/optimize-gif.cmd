@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimize-gif.ps1" %*
exit /b %errorlevel%

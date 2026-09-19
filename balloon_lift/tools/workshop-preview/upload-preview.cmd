@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload-preview.ps1" %*
exit /b %errorlevel%

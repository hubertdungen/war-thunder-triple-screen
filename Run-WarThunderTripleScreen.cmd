@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WarThunderTripleScreen.ps1" %*
set "WTTS_EXIT=%ERRORLEVEL%"
echo.
if not "%WTTS_EXIT%"=="0" echo War Thunder Triple Screen terminou com o codigo %WTTS_EXIT%.
pause
exit /b %WTTS_EXIT%


@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WarThunderTripleScreen.ps1" -Attach %*
set "WTTS_EXIT=%ERRORLEVEL%"
echo.
if not "%WTTS_EXIT%"=="0" echo A correcao da janela terminou com o codigo %WTTS_EXIT%.
pause
exit /b %WTTS_EXIT%


@echo off
setlocal
cd /d "%~dp0"
set "LEVE_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LEVE_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LEVE_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Leve11.ps1"
if errorlevel 1 pause
endlocal

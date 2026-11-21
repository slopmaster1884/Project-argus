@echo off
rem Argus node for Windows: double-click this file (or run it from cmd) to turn this PC into an Argus node.
rem It starts argus-node-windows.ps1 with ExecutionPolicy Bypass, so no PowerShell settings need changing.
rem If the .ps1 is not next to this file, it is downloaded from GitHub into %TEMP%.
rem   argus-node-windows.cmd              run in this window (Ctrl+C stops)
rem   argus-node-windows.cmd -Install     autostart at logon
rem   argus-node-windows.cmd -Uninstall   remove everything
setlocal
chcp 65001 >nul
set "PS1=%~dp0argus-node-windows.ps1"
if not exist "%PS1%" (
  set "PS1=%TEMP%\argus-node-windows.ps1"
  echo [argus-node] Downloading argus-node-windows.ps1 ...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/argus-node-windows.ps1' -OutFile $env:TEMP\argus-node-windows.ps1"
)
if not exist "%PS1%" (
  echo [argus-node] ERROR: could not get argus-node-windows.ps1. Check the internet connection.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
if not defined ARGUS_NO_PAUSE pause
exit /b %RC%

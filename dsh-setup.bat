@echo off
setlocal EnableExtensions
title DeepSeek Harness Installer
cd /d "%~dp0"

rem ---- Config: bump NODE_VER to a newer Node LTS if ever needed ----
set "NODE_VER=v24.20.0"
set "RUNTIME=%~dp0dsh-runtime"
set "NODE_DIR=%RUNTIME%\node"
set "NPM=%NODE_DIR%\npm.cmd"
set "DSH=%NODE_DIR%\dsh.cmd"

echo ============================================================
echo   DeepSeek Harness  One-Click Installer  (Windows 10 x64)
echo   Portable Node + China npm mirror. No git / admin / GitHub.
echo ============================================================
echo.

rem ---- 1) Portable Node.js (skip if already present) ----
if exist "%NODE_DIR%\node.exe" goto node_ready

echo [1/3] Downloading portable Node.js %NODE_VER% ...
if not exist "%RUNTIME%" mkdir "%RUNTIME%"
curl -L --fail --retry 3 --connect-timeout 20 -o "%RUNTIME%\node.zip" "https://npmmirror.com/mirrors/node/%NODE_VER%/node-%NODE_VER%-win-x64.zip"
if errorlevel 1 (
    echo.
    echo Download failed. Check network, then run this again.
    pause
    exit /b 1
)

echo [2/3] Extracting ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%RUNTIME%\node.zip' -DestinationPath '%RUNTIME%' -Force"
del "%RUNTIME%\node.zip" >nul 2>nul
if exist "%NODE_DIR%" rmdir /s /q "%NODE_DIR%"
ren "%RUNTIME%\node-%NODE_VER%-win-x64" node
echo       Node version:
"%NODE_DIR%\node.exe" --version

:node_ready

rem ---- 2) npm registry -> China mirror ----
echo.
echo [3/3] Configure npm mirror + install dsh ...
call "%NPM%" config set registry https://registry.npmmirror.com

if not exist "%DSH%" (
    echo       Installing @deepseek-ai/dsh. This may take a few minutes...
    call "%NPM%" install -g @deepseek-ai/dsh --prefix "%NODE_DIR%" --no-fund --no-audit
    if errorlevel 1 (
        echo.
        echo dsh install failed. Check network, then run this again.
        pause
        exit /b 1
    )
) else (
    echo       dsh already installed, skip.
)

if not exist "%DSH%" (
    echo.
    echo ERROR: install finished but dsh.cmd was not found in:
    echo   %NODE_DIR%
    echo Run this again, or copy the error text and send it to us.
    pause
    exit /b 1
)

rem ---- 3) Launch ----
echo.
echo ============================================================
echo   INSTALL COMPLETE.  Starting the Web UI server ...
echo.
echo   1) Keep this black window OPEN while you use dsh.
echo   2) First launch may take 30-60 seconds.
echo   3) The browser should open automatically.
echo      If it does NOT open, copy the full address that
echo      contains ?token= from the lines below and paste
echo      it into your browser's address bar.
echo ============================================================
echo.
call "%DSH%" web

echo.
echo Server stopped. Press any key to close this window.
pause

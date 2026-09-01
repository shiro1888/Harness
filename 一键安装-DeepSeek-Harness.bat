@echo off
chcp 65001 >nul
title DeepSeek Harness - One-Click Installer
echo ============================================================
echo   DeepSeek Harness  One-Click Installer
echo   Portable Node.js + China npm mirror.
echo   No git, no admin, no GitHub needed.
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-dsh.ps1"
echo.
echo ---- Finished. If the Web UI did not open, double-click: 启动-DeepSeek-Harness.bat ----
pause

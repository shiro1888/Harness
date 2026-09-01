@echo off
chcp 65001 >nul
title DeepSeek Harness
set "PATH=%~dp0dsh-runtime\node;%PATH%"
dsh web
pause

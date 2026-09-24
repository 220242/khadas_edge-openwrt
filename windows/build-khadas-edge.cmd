@echo off
rem Khadas Edge OpenWrt build (Windows 11 + WSL2): runs build-khadas-edge.ps1
rem Usage: build-khadas-edge.cmd [-Root D:\KhadasEdgeBuild] [-Jobs 8] [-Clean] [-NoBuild] [-Uninstall]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-khadas-edge.ps1" %*
pause

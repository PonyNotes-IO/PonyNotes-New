@echo off
:: Wrapper script - forwards to build_installer.ps1
:: This ensures compatibility with both cmd and PowerShell environments

powershell -ExecutionPolicy Bypass -File "%~dp0build_installer.ps1" %*

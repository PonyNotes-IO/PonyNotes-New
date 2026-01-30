@echo off
chcp 65001 >nul
echo ============================================
echo   PonyNotes Windows 安装包构建脚本
echo ============================================
echo.

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "FRONTEND_DIR=%SCRIPT_DIR%..\.."
set "INSTALL_DIR=%SCRIPT_DIR%AppFlowy"
set "OUTPUT_DIR=%SCRIPT_DIR%Output"

REM 设置版本号（可修改）
set "VERSION=0.9.9"

REM 设置 Inno Setup 编译器路径（如果不在 PATH 中，使用绝对路径）
set "ISCC_PATH=D:\Inno Setup 6\ISCC.exe"
if not exist "%ISCC_PATH%" (
    where iscc >nul 2>&1
    if %errorlevel% neq 0 (
        echo 错误: 未找到 Inno Setup 编译器 (iscc.exe)
        echo 请安装 Inno Setup: https://jrsoftware.org/isdl.php
        echo 并确保 iscc.exe 在系统 PATH 中，或修改脚本中的 ISCC_PATH
        exit /b 1
    )
    set "ISCC_PATH=iscc"
)
echo ✓ Inno Setup 编译器已找到

echo.
echo [2/5] 检查 Flutter Release 构建产物...
if not exist "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\runner\Release\AppFlowy.exe" (
    echo 错误: 未找到 Flutter Release 构建产物
    echo 请先运行: flutter build windows --release
    exit /b 1
)
echo ✓ Flutter Release 构建产物已找到

echo.
echo [3/5] 检查 Rust Release 构建产物...
if not exist "%FRONTEND_DIR%\rust-lib\target\release\deps\*.dll" (
    echo 警告: 未找到 Rust Release DLL，将使用已有的依赖
)
echo ✓ Rust 构建产物检查完成

echo.
echo [4/5] 准备安装目录...
REM 清理旧的安装目录
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%" 2>nul
mkdir "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%\data"

REM 复制 Flutter 构建产物
echo 复制 Flutter 构建产物...
xcopy "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\runner\Release\*" "%INSTALL_DIR%\" /E /H /Y >nul

REM 复制 Rust DLL 依赖
echo 复制 Rust DLL 依赖...
for %%f in ("%FRONTEND_DIR%\rust-lib\target\release\deps\*.dll") do (
    if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM 复制额外的必要文件
if exist "%FRONTEND_DIR%\rust-lib\target\release\*.dll" (
    for %%f in ("%FRONTEND_DIR%\rust-lib\target\release\*.dll") do (
        copy "%%f" "%INSTALL_DIR%\" /Y >nul
    )
)

echo ✓ 安装目录准备完成

echo.
echo [5/5] 编译安装包...
REM 清理旧的输出目录
if exist "%OUTPUT_DIR%" rmdir /s /q "%OUTPUT_DIR%" 2>nul
mkdir "%OUTPUT_DIR%"

REM 执行编译
"%ISCC_PATH%" "%SCRIPT_DIR%inno_setup_config.iss"
if %errorlevel% equ 0 (
    echo ✓ 安装包编译成功!
) else (
    echo 错误: 安装包编译失败
    exit /b 1
)

echo.
echo ============================================
echo   构建完成!
echo ============================================
echo.
echo 安装包位置: %OUTPUT_DIR%
echo.
if exist "%OUTPUT_DIR%\PonyNotesSetup.exe" (
    echo ✓ 安装包文件: %OUTPUT_DIR%\PonyNotesSetup.exe
    echo.
    echo 安装包大小:
    for %%I in ("%OUTPUT_DIR%\PonyNotesSetup.exe") do echo   - %%~zI 字节
) else (
    echo 警告: 未找到 PonyNotesSetup.exe 文件
)
echo.
exit /b 0


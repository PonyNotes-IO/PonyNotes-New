#!/bin/bash
# =============================================================================
# 自动检测设备架构并构建对应的Rust库（非交互式版本，用于VSCode任务）
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"

cd "$FRONTEND_DIR"

echo "=========================================="
echo "  自动检测架构并构建 Appflowy Core"
echo "=========================================="

# =============================================================================
# 1. 检测设备架构
# =============================================================================
MACHINE_ARCH=$(uname -m)
echo "设备架构: $MACHINE_ARCH"

# =============================================================================
# 2. 检测Flutter运行模式
# =============================================================================
# 直接使用系统Flutter命令
FLUTTER_CMD="flutter"

FLUTTER_ARCH=""

if [ -n "$FLUTTER_CMD" ]; then
    FLUTTER_INFO=$($FLUTTER_CMD doctor -v 2>/dev/null | grep -E "darwin-arm64|darwin-x64|Rosetta" || echo "")
    
    if echo "$FLUTTER_INFO" | grep -q "Rosetta"; then
        FLUTTER_ARCH="x86_64"
        echo "Flutter模式: Rosetta (需要x86_64库)"
    elif echo "$FLUTTER_INFO" | grep -q "darwin-arm64"; then
        FLUTTER_ARCH="arm64"
        echo "Flutter模式: 原生arm64"
    elif echo "$FLUTTER_INFO" | grep -q "darwin-x64\|darwin-x86_64"; then
        FLUTTER_ARCH="x86_64"
        echo "Flutter模式: 原生x86_64"
    else
        FLUTTER_ARCH="$MACHINE_ARCH"
        echo "Flutter模式: 使用设备架构 $MACHINE_ARCH"
    fi
else
    FLUTTER_ARCH="$MACHINE_ARCH"
    echo "Flutter模式: Flutter未找到，使用设备架构 $MACHINE_ARCH"
fi

# =============================================================================
# 3. 确定最终构建架构
# =============================================================================
if [ "$FLUTTER_ARCH" = "arm64" ]; then
    PROFILE="development-mac-arm64"
    TARGET_ARCH="arm64"
elif [ "$FLUTTER_ARCH" = "x86_64" ]; then
    PROFILE="development-mac-x86_64"
    TARGET_ARCH="x86_64"
else
    if [ "$MACHINE_ARCH" = "arm64" ]; then
        PROFILE="development-mac-arm64"
        TARGET_ARCH="arm64"
    else
        PROFILE="development-mac-x86_64"
        TARGET_ARCH="x86_64"
    fi
fi

echo "选择构建配置: $PROFILE"
echo "目标架构: $TARGET_ARCH"

# =============================================================================
# 4. 检查现有库文件架构，如果不匹配则删除
# =============================================================================
LIB_PATH="appflowy_flutter/packages/appflowy_backend/macos/libdart_ffi.a"

if [ -f "$LIB_PATH" ]; then
    CURRENT_ARCH=$(lipo -info "$LIB_PATH" 2>/dev/null | awk -F': ' '{print $NF}' || echo "unknown")
    echo "现有库架构: $CURRENT_ARCH"
    
    if [ "$CURRENT_ARCH" = "$TARGET_ARCH" ]; then
        echo "✓ 库文件架构匹配，跳过构建"
        exit 0
    else
        echo "✗ 库文件架构不匹配，删除并重新构建"
        rm -f "$LIB_PATH"
    fi
else
    echo "库文件不存在，需要构建"
fi

# =============================================================================
# 5. 执行构建
# =============================================================================
echo ""
echo "开始构建 (profile: $PROFILE)..."
echo ""

cargo make --profile "$PROFILE" appflowy-core-dev

# =============================================================================
# 6. 验证构建结果
# =============================================================================
if [ -f "$LIB_PATH" ]; then
    FINAL_ARCH=$(lipo -info "$LIB_PATH" 2>/dev/null | awk -F': ' '{print $NF}' || echo "unknown")
    if [ "$FINAL_ARCH" = "$TARGET_ARCH" ]; then
        echo "✓ 构建成功！库文件架构: $FINAL_ARCH"
    else
        echo "✗ 警告：库文件架构 ($FINAL_ARCH) 与目标架构 ($TARGET_ARCH) 不匹配"
        exit 1
    fi
else
    echo "✗ 错误：库文件未生成"
    exit 1
fi

echo ""
echo "=========================================="
echo "  构建完成！"
echo "=========================================="


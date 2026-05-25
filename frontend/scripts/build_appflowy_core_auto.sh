#!/bin/bash
# =============================================================================
# 自动检测设备架构并构建对应的Rust库
# 
# 功能：
# 1. 检测设备CPU架构（arm64/x86_64）
# 2. 检测Flutter运行模式（原生/Rosetta）
# 3. 自动选择正确的构建配置
# =============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  自动检测架构并构建 Appflowy Core${NC}"
echo -e "${BLUE}========================================${NC}"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"

cd "$FRONTEND_DIR"

# =============================================================================
# 1. 检测设备架构
# =============================================================================
MACHINE_ARCH=$(uname -m)
echo -e "${YELLOW}设备架构: ${NC}${MACHINE_ARCH}"

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
        echo -e "${YELLOW}Flutter模式: ${NC}Rosetta (需要x86_64库)"
    elif echo "$FLUTTER_INFO" | grep -q "darwin-arm64"; then
        FLUTTER_ARCH="arm64"
        echo -e "${YELLOW}Flutter模式: ${NC}原生arm64"
    elif echo "$FLUTTER_INFO" | grep -q "darwin-x64\|darwin-x86_64"; then
        FLUTTER_ARCH="x86_64"
        echo -e "${YELLOW}Flutter模式: ${NC}原生x86_64"
    else
        FLUTTER_ARCH="$MACHINE_ARCH"
        echo -e "${YELLOW}Flutter模式: ${NC}使用设备架构 $MACHINE_ARCH"
    fi
else
    FLUTTER_ARCH="$MACHINE_ARCH"
    echo -e "${YELLOW}Flutter模式: ${NC}Flutter未找到，使用设备架构 $MACHINE_ARCH"
fi

# =============================================================================
# 3. 确定最终构建架构
# =============================================================================
# 优先使用Flutter的架构需求，因为最终是Flutter链接这个库
if [ "$FLUTTER_ARCH" = "arm64" ]; then
    PROFILE="development-mac-arm64"
    TARGET_ARCH="arm64"
elif [ "$FLUTTER_ARCH" = "x86_64" ]; then
    PROFILE="development-mac-x86_64"
    TARGET_ARCH="x86_64"
else
    # 默认使用设备架构
    if [ "$MACHINE_ARCH" = "arm64" ]; then
        PROFILE="development-mac-arm64"
        TARGET_ARCH="arm64"
    else
        PROFILE="development-mac-x86_64"
        TARGET_ARCH="x86_64"
    fi
fi

echo -e "${GREEN}选择构建配置: ${NC}${PROFILE}"
echo -e "${GREEN}目标架构: ${NC}${TARGET_ARCH}"

# =============================================================================
# 4. 检查现有库文件架构
# =============================================================================
LIB_PATH="appflowy_flutter/packages/appflowy_backend/macos/libdart_ffi.a"

if [ -f "$LIB_PATH" ]; then
    CURRENT_ARCH=$(lipo -info "$LIB_PATH" 2>/dev/null | awk -F': ' '{print $NF}' || echo "unknown")
    echo -e "${YELLOW}现有库架构: ${NC}${CURRENT_ARCH}"
    
    if [ "$CURRENT_ARCH" = "$TARGET_ARCH" ]; then
        echo -e "${GREEN}✓ 库文件架构匹配，无需重新构建${NC}"
        read -p "是否强制重新构建? (y/N): " -n 1 -r FORCE_BUILD
        echo
        if [[ ! $FORCE_BUILD =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}跳过构建${NC}"
            exit 0
        fi
    else
        echo -e "${RED}✗ 库文件架构不匹配，需要重新构建${NC}"
        echo -e "  当前: ${CURRENT_ARCH}"
        echo -e "  需要: ${TARGET_ARCH}"
        rm -f "$LIB_PATH"
        echo -e "${YELLOW}已删除旧库文件${NC}"
    fi
else
    echo -e "${YELLOW}库文件不存在，需要构建${NC}"
fi

# =============================================================================
# 5. 执行构建
# =============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  开始构建 (profile: ${PROFILE})${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cargo make --profile "$PROFILE" appflowy-core-dev

# =============================================================================
# 6. 验证构建结果
# =============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  验证构建结果${NC}"
echo -e "${BLUE}========================================${NC}"

if [ -f "$LIB_PATH" ]; then
    FINAL_ARCH=$(lipo -info "$LIB_PATH" 2>/dev/null | awk -F': ' '{print $NF}' || echo "unknown")
    if [ "$FINAL_ARCH" = "$TARGET_ARCH" ]; then
        echo -e "${GREEN}✓ 构建成功！库文件架构: ${FINAL_ARCH}${NC}"
    else
        echo -e "${RED}✗ 警告：库文件架构 (${FINAL_ARCH}) 与目标架构 (${TARGET_ARCH}) 不匹配${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ 错误：库文件未生成${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  构建完成！现在可以启动调试了${NC}"
echo -e "${GREEN}========================================${NC}"


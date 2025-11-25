#!/bin/bash

# 重新签名 macOS 应用脚本
# 用于修复 HotKey.framework 等框架的代码签名问题

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始重新签名 macOS 应用...${NC}"

# 检测应用路径
APP_PATH="${1:-build/macos/Build/Products/Release/PonyNotes.app}"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}错误: 找不到应用: $APP_PATH${NC}"
    echo "用法: $0 [应用路径]"
    echo "示例: $0 build/macos/Build/Products/Release/PonyNotes.app"
    exit 1
fi

echo -e "${YELLOW}应用路径: $APP_PATH${NC}"

# 检测签名身份
# 首先尝试自动检测
SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$SIGN_IDENTITY" ]; then
    echo -e "${YELLOW}未找到有效的签名证书，使用 ad-hoc 签名（-）${NC}"
    SIGN_IDENTITY="-"
else
    echo -e "${GREEN}使用签名证书: $SIGN_IDENTITY${NC}"
fi

# 函数：重新签名框架
resign_framework() {
    local framework_path="$1"
    if [ -d "$framework_path" ]; then
        echo -e "${YELLOW}重新签名: $framework_path${NC}"
        codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$framework_path" 2>/dev/null || \
        codesign --force --deep --sign "$SIGN_IDENTITY" "$framework_path" 2>/dev/null || true
    fi
}

# 函数：重新签名插件
resign_plugin() {
    local plugin_path="$1"
    if [ -d "$plugin_path" ]; then
        echo -e "${YELLOW}重新签名插件: $plugin_path${NC}"
        codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$plugin_path" 2>/dev/null || \
        codesign --force --deep --sign "$SIGN_IDENTITY" "$plugin_path" 2>/dev/null || true
    fi
}

# 1. 重新签名所有 Frameworks
echo -e "${GREEN}步骤 1: 重新签名所有 Frameworks...${NC}"
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null | while read framework; do
    resign_framework "$framework"
done

# 2. 重新签名所有 Plugins
echo -e "${GREEN}步骤 2: 重新签名所有 Plugins...${NC}"
find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d 2>/dev/null | while read plugin; do
    resign_plugin "$plugin"
done

# 3. 重新签名所有 dylib
echo -e "${GREEN}步骤 3: 重新签名所有 dylib...${NC}"
find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null | while read dylib; do
    echo -e "${YELLOW}重新签名: $dylib${NC}"
    codesign --force --sign "$SIGN_IDENTITY" "$dylib" 2>/dev/null || true
done

# 4. 重新签名所有可执行文件
echo -e "${GREEN}步骤 4: 重新签名所有可执行文件...${NC}"
find "$APP_PATH/Contents" -type f -perm +111 -exec sh -c 'file "{}" | grep -q "Mach-O" && echo "{}"' \; 2>/dev/null | while read binary; do
    if [[ "$binary" != *".app/Contents/MacOS/PonyNotes" ]]; then
        echo -e "${YELLOW}重新签名: $binary${NC}"
        codesign --force --sign "$SIGN_IDENTITY" "$binary" 2>/dev/null || true
    fi
done

# 5. 最后重新签名主应用
echo -e "${GREEN}步骤 5: 重新签名主应用...${NC}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
else
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

# 6. 验证签名
echo -e "${GREEN}步骤 6: 验证签名...${NC}"
if codesign -vvv "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
    echo -e "${GREEN}✓ 签名验证成功！${NC}"
else
    echo -e "${RED}✗ 签名验证失败${NC}"
    codesign -vvv "$APP_PATH"
    exit 1
fi

# 7. 检查特定框架
echo -e "${GREEN}步骤 7: 检查 HotKey.framework...${NC}"
HOTKEY_FRAMEWORK="$APP_PATH/Contents/Frameworks/HotKey.framework"
if [ -d "$HOTKEY_FRAMEWORK" ]; then
    if codesign -vvv "$HOTKEY_FRAMEWORK" 2>&1 | grep -q "valid on disk"; then
        echo -e "${GREEN}✓ HotKey.framework 签名有效${NC}"
    else
        echo -e "${YELLOW}⚠ HotKey.framework 签名可能有问题${NC}"
        codesign -vvv "$HOTKEY_FRAMEWORK"
    fi
else
    echo -e "${YELLOW}⚠ 未找到 HotKey.framework${NC}"
fi

echo -e "${GREEN}重新签名完成！${NC}"
echo -e "${GREEN}应用路径: $APP_PATH${NC}"


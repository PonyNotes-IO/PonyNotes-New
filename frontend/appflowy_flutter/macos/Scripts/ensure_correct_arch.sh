#!/bin/bash
# =============================================================================
# 确保 libdart_ffi.a 使用正确的架构
# 
# 此脚本会在 Xcode 构建前运行，自动检测并选择正确架构的库文件
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$(dirname "$MACOS_DIR")"

# 库文件路径
LIB_DIR="$FLUTTER_DIR/packages/appflowy_backend/macos"
LIB_FILE="$LIB_DIR/libdart_ffi.a"
LIB_ARM64="$LIB_DIR/libdart_ffi.a.arm64"
LIB_X86_64="$LIB_DIR/libdart_ffi.a.x86_64"

echo "=== 架构检测脚本 ==="
echo "库文件目录: $LIB_DIR"

# 检测目标架构
# 优先使用 Xcode 构建设置中的架构
if [ -n "$ARCHS" ]; then
    TARGET_ARCH="$ARCHS"
    echo "使用 Xcode 构建架构: $TARGET_ARCH"
elif [ -n "$NATIVE_ARCH" ]; then
    TARGET_ARCH="$NATIVE_ARCH"
    echo "使用 NATIVE_ARCH: $TARGET_ARCH"
else
    # 使用机器原生架构
    MACHINE_ARCH=$(uname -m)
    TARGET_ARCH="$MACHINE_ARCH"
    echo "使用机器架构: $TARGET_ARCH"
fi

# 标准化架构名称
case "$TARGET_ARCH" in
    "arm64" | "aarch64")
        REQUIRED_ARCH="arm64"
        ;;
    "x86_64" | "x64")
        REQUIRED_ARCH="x86_64"
        ;;
    *)
        # 如果包含多个架构，选择第一个
        FIRST_ARCH=$(echo "$TARGET_ARCH" | awk '{print $1}')
        case "$FIRST_ARCH" in
            "arm64" | "aarch64")
                REQUIRED_ARCH="arm64"
                ;;
            *)
                REQUIRED_ARCH="x86_64"
                ;;
        esac
        ;;
esac

echo "需要的架构: $REQUIRED_ARCH"

# 检查当前库文件架构
if [ -f "$LIB_FILE" ]; then
    CURRENT_ARCH=$(lipo -info "$LIB_FILE" 2>/dev/null | awk -F': ' '{print $NF}' | tr -d ' ')
    echo "当前库架构: $CURRENT_ARCH"
    
    # 检查是否是 fat/universal binary
    if echo "$CURRENT_ARCH" | grep -q " "; then
        echo "✓ 库是 universal binary，包含多架构: $CURRENT_ARCH"
        exit 0
    fi
    
    # 检查架构是否匹配
    if [ "$CURRENT_ARCH" = "$REQUIRED_ARCH" ]; then
        echo "✓ 架构匹配，无需更换"
        exit 0
    else
        echo "✗ 架构不匹配，需要更换 (当前: $CURRENT_ARCH, 需要: $REQUIRED_ARCH)"
    fi
else
    echo "✗ 库文件不存在"
fi

# 选择正确架构的库文件
if [ "$REQUIRED_ARCH" = "arm64" ]; then
    SOURCE_LIB="$LIB_ARM64"
elif [ "$REQUIRED_ARCH" = "x86_64" ]; then
    SOURCE_LIB="$LIB_X86_64"
fi

# 尝试从备份恢复
if [ -f "$SOURCE_LIB" ]; then
    echo "从备份恢复: $SOURCE_LIB"
    cp "$SOURCE_LIB" "$LIB_FILE"
    echo "✓ 已替换为 $REQUIRED_ARCH 架构的库文件"
    lipo -info "$LIB_FILE"
else
    echo "⚠ 警告: 未找到 $REQUIRED_ARCH 架构的备份库文件"
    echo "  请手动运行构建: ./scripts/build_appflowy_core_auto.sh"
    
    # 尝试查找 rust-lib 构建目录中的库
    RUST_LIB_DIR="$FLUTTER_DIR/../rust-lib/target"
    
    if [ "$REQUIRED_ARCH" = "arm64" ]; then
        RUST_TARGET="aarch64-apple-darwin"
    else
        RUST_TARGET="x86_64-apple-darwin"
    fi
    
    for BUILD_TYPE in debug release; do
        RUST_LIB="$RUST_LIB_DIR/$RUST_TARGET/$BUILD_TYPE/libdart_ffi.a"
        if [ -f "$RUST_LIB" ]; then
            echo "从 Rust 构建目录恢复: $RUST_LIB"
            cp "$RUST_LIB" "$LIB_FILE"
            # 同时保存备份
            cp "$RUST_LIB" "$SOURCE_LIB"
            echo "✓ 已使用 Rust 构建的 $REQUIRED_ARCH 库文件"
            lipo -info "$LIB_FILE"
            exit 0
        fi
    done
    
    echo "✗ 错误: 无法找到 $REQUIRED_ARCH 架构的库文件"
    echo "  可用的库文件:"
    ls -la "$LIB_DIR"/libdart_ffi.a* 2>/dev/null || echo "  (无)"
    exit 1
fi

echo "=== 架构检测完成 ==="


















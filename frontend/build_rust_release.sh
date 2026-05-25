#!/bin/bash
# 构建 Rust 库（Release 模式）并复制到 Flutter 应用目录
# 使用方法: ./build_rust_release.sh

# 不使用 set -e，以便在 cargo make 失败时能继续执行 cargo build
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR"
RUST_LIB_DIR="$FRONTEND_DIR/rust-lib"
FLUTTER_LIB_DIR="$FRONTEND_DIR/appflowy_flutter/packages/appflowy_backend/macos"

# 检测机器架构
MACHINE_ARCH=$(uname -m)
if [ "$MACHINE_ARCH" = "arm64" ]; then
    PROFILE="production-mac-arm64"
    RUST_TARGET="aarch64-apple-darwin"
elif [ "$MACHINE_ARCH" = "x86_64" ]; then
    PROFILE="production-mac-x86_64"
    RUST_TARGET="x86_64-apple-darwin"
else
    echo "错误: 不支持的架构: $MACHINE_ARCH"
    exit 1
fi

echo "=========================================="
echo "  构建 Rust 库 (Release 模式)"
echo "=========================================="
echo "机器架构: $MACHINE_ARCH"
echo "使用 Profile: $PROFILE"
echo "Rust Target: $RUST_TARGET"
echo ""

cd "$FRONTEND_DIR"

# 方法1: 使用 cargo make（如果可用）
if command -v cargo-make &> /dev/null || command -v cargo make &> /dev/null; then
    echo "尝试使用 cargo make 构建..."
    if cargo make --profile "$PROFILE" appflowy-core-release 2>&1; then
        # 验证库文件是否已复制
        if [ -f "$FLUTTER_LIB_DIR/libdart_ffi.a" ]; then
            echo ""
            echo "✅ 构建完成！库文件已自动复制到 Flutter 应用目录"
            ls -lh "$FLUTTER_LIB_DIR/libdart_ffi.a"
            exit 0
        else
            echo "⚠️ 警告: cargo make 构建完成，但库文件未找到，尝试手动复制..."
        fi
    else
        EXIT_CODE=$?
        echo ""
        echo "⚠️ cargo make 构建失败 (退出代码: $EXIT_CODE)"
        echo "将使用 cargo build 直接构建..."
        echo ""
    fi
fi

# 方法2: 直接使用 cargo build（备用方案）
echo "使用 cargo build 直接构建..."
cd "$RUST_LIB_DIR"

echo "开始构建 (这可能需要几分钟)..."
set -e  # 现在启用错误检查
cargo build --release --package=dart-ffi --target "$RUST_TARGET" --features "dart"

# 查找构建好的库文件
LIB_SOURCE="$RUST_LIB_DIR/target/$RUST_TARGET/release/libdart_ffi.a"
LIB_DEST="$FLUTTER_LIB_DIR/libdart_ffi.a"

if [ ! -f "$LIB_SOURCE" ]; then
    echo "错误: 未找到构建好的库文件: $LIB_SOURCE"
    exit 1
fi

# 备份旧文件
if [ -f "$LIB_DEST" ]; then
    BACKUP_FILE="${LIB_DEST}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "备份旧库文件到: $BACKUP_FILE"
    cp "$LIB_DEST" "$BACKUP_FILE"
fi

# 复制库文件
echo "复制库文件到 Flutter 应用目录..."
mkdir -p "$FLUTTER_LIB_DIR"
cp "$LIB_SOURCE" "$LIB_DEST"

# 复制 binding.h（如果存在）
BINDING_SOURCE="$RUST_LIB_DIR/dart-ffi/binding.h"
BINDING_DEST="$FLUTTER_LIB_DIR/Classes/binding.h"
if [ -f "$BINDING_SOURCE" ]; then
    echo "复制 binding.h..."
    mkdir -p "$FLUTTER_LIB_DIR/Classes"
    cp "$BINDING_SOURCE" "$BINDING_DEST"
fi

# 验证
echo ""
echo "✅ 构建完成！"
echo "验证库文件:"
ls -lh "$LIB_DEST"
file "$LIB_DEST" || true

echo ""
echo "=========================================="
echo "  现在可以启动 Flutter 应用了！"
echo "=========================================="

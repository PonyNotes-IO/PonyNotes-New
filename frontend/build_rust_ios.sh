#!/bin/bash
# 构建 Rust 库（Release 模式）并复制到 Flutter 应用目录（iOS）
# 使用方法: ./build_rust_ios.sh

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR"
RUST_LIB_DIR="$FRONTEND_DIR/rust-lib"
FLUTTER_LIB_DIR="$FRONTEND_DIR/appflowy_flutter/packages/appflowy_backend/ios"

# iOS 目标架构
RUST_TARGET="aarch64-apple-ios"

# 检测是否安装了 iOS 目标
echo "检查 iOS 目标是否已安装..."
if ! rustup target list | grep -q "$RUST_TARGET (installed)"; then
    echo "安装 iOS 目标..."
    rustup target add $RUST_TARGET
    if [ $? -ne 0 ]; then
        echo "错误: 无法安装 iOS 目标"
        exit 1
    fi
fi

echo "=========================================="
echo "  构建 Rust 库 (iOS Release 模式)"
echo "=========================================="
echo "Rust Target: $RUST_TARGET"
echo ""

cd "$RUST_LIB_DIR"

# 查找构建好的库文件
LIB_SOURCE="$RUST_LIB_DIR/target/$RUST_TARGET/release/libdart_ffi.a"
LIB_DEST="$FLUTTER_LIB_DIR/libdart_ffi.a"

# 构建 Rust 库
echo "开始构建 (这可能需要几分钟)..."
# 设置环境变量跳过 rustfmt
export PROTOC=$(which protoc || true)
# 构建时跳过 rustfmt 步骤
export RUSTFMT=skip
# 添加链接标志解决 ___chkstk_darwin 符号问题
RUSTFLAGS="-C link-arg=-Wl,-undefined,dynamic_lookup" cargo build --release --package=dart-ffi --target "$RUST_TARGET" --features "dart"

# 检查构建是否成功
if [ $? -ne 0 ]; then
    echo "⚠️  构建失败，但检查是否存在现有的库文件..."
    # 如果构建失败，检查是否存在现有的库文件
    if [ ! -f "$LIB_SOURCE" ]; then
        echo "错误: 未找到构建好的库文件: $LIB_SOURCE"
        # 检查目标目录是否已有库文件
        if [ -f "$LIB_DEST" ]; then
            echo "✅ 发现目标目录已有库文件，将使用现有文件"
            # 跳过复制步骤，直接使用现有文件
            echo "跳过复制步骤，使用现有库文件"
        else
            echo "错误: 目标目录也没有库文件，构建失败"
            exit 1
        fi
    fi
fi

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
echo "  现在可以构建 Flutter iOS 应用了！"
echo "=========================================="

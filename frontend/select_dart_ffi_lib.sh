#!/bin/bash
# 根据机器架构选择合适的 libdart_ffi.a 文件
# 用于解决 CocoaPods 无法处理大型 universal binary 的问题

set -e

TARGET_DIR="PonyNotes-New/frontend/appflowy_flutter/packages/appflowy_backend/macos"
LIB_PATH="$TARGET_DIR/libdart_ffi.a"

# 备份当前文件
if [ -f "$LIB_PATH" ]; then
    cp "$LIB_PATH" "$LIB_PATH.backup.$(date +%Y%m%d_%H%M%S)"
fi

# 检测机器架构
MACHINE_ARCH=$(uname -m)

echo "检测到机器架构: $MACHINE_ARCH"

if [ "$MACHINE_ARCH" = "arm64" ]; then
    echo "Apple Silicon Mac: 使用 arm64 版本"
    # 对于 Apple Silicon，使用现有的 arm64 版本（应该已经存在）
    if [ -f "$TARGET_DIR/libdart_ffi.a.backup" ]; then
        cp "$TARGET_DIR/libdart_ffi.a.backup" "$LIB_PATH"
    fi
elif [ "$MACHINE_ARCH" = "x86_64" ]; then
    echo "Intel Mac: 使用 x86_64 版本"
    # 对于 Intel Mac，使用 x86_64 版本
    X86_LIB="../../../rust-lib/target/x86_64-apple-darwin/release/libdart_ffi.a"
    if [ -f "$X86_LIB" ]; then
        cp "$X86_LIB" "$LIB_PATH"
    else
        echo "错误: 未找到 x86_64 版本的库文件: $X86_LIB"
        echo "请先构建 x86_64 版本: cargo build --release --target x86_64-apple-darwin"
        exit 1
    fi
else
    echo "错误: 不支持的架构: $MACHINE_ARCH"
    exit 1
fi

echo "验证库文件:"
ls -lh "$LIB_PATH"
lipo -info "$LIB_PATH"

echo "完成！"

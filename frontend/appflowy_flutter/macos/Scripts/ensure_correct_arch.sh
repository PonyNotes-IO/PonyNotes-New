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
    MACHINE_ARCH=$(uname -m)
    TARGET_ARCH="$MACHINE_ARCH"
    echo "使用机器架构: $TARGET_ARCH"
fi

# ── Universal 构建快速通道 ──────────────────────────────────
# 当 ARCHS 包含多个架构时（如 "arm64 x86_64"），必须使用 universal binary。
# 用 lipo -archs 检测（输出干净的 "x86_64 arm64"，无多余文本）。
ARCH_COUNT=$(echo "$TARGET_ARCH" | wc -w | tr -d ' ')
if [ "$ARCH_COUNT" -gt 1 ]; then
    echo "Universal 构建模式 (ARCHS=$TARGET_ARCH)"
    if [ -f "$LIB_FILE" ]; then
        # lipo -archs 输出格式: "x86_64 arm64"（含空格即为 fat binary）
        CURRENT_ARCHS=$(lipo -archs "$LIB_FILE" 2>/dev/null || echo "")
        CURRENT_COUNT=$(echo "$CURRENT_ARCHS" | wc -w | tr -d ' ')
        if [ "$CURRENT_COUNT" -gt 1 ]; then
            echo "✓ libdart_ffi.a 已是 universal binary: $CURRENT_ARCHS"
            echo "=== 架构检测完成 ==="
            exit 0
        else
            echo "✗ libdart_ffi.a 不是 universal binary (当前: $CURRENT_ARCHS)"
            echo "  请先运行 build_macos_dmg.sh 或手动执行 lipo 合并"
            echo "  尝试从 Rust 构建目录重新合并..."
            RUST_LIB_DIR="$FLUTTER_DIR/../rust-lib/target"
            ARM64_LIB="$RUST_LIB_DIR/aarch64-apple-darwin/release/libdart_ffi.a"
            X86_LIB="$RUST_LIB_DIR/x86_64-apple-darwin/release/libdart_ffi.a"
            if [ -f "$ARM64_LIB" ] && [ -f "$X86_LIB" ]; then
                lipo -create "$X86_LIB" "$ARM64_LIB" -output "$LIB_FILE"
                echo "✓ 已重新合并 universal binary: $(lipo -archs "$LIB_FILE")"
                echo "=== 架构检测完成 ==="
                exit 0
            else
                echo "✗ 错误: 找不到 arm64/x86_64 的 Rust 构建产物，无法合并"
                exit 1
            fi
        fi
    else
        echo "✗ libdart_ffi.a 不存在，universal 构建无法继续"
        exit 1
    fi
fi
# ────────────────────────────────────────────────────────────

# 单架构构建逻辑（arm64 或 x86_64）
case "$TARGET_ARCH" in
    "arm64" | "aarch64")
        REQUIRED_ARCH="arm64"
        ;;
    "x86_64" | "x64")
        REQUIRED_ARCH="x86_64"
        ;;
    *)
        REQUIRED_ARCH="arm64"
        ;;
esac

echo "需要的架构: $REQUIRED_ARCH"

# 检查当前库文件架构（用 lipo -archs，不做 tr -d ' ' 处理）
if [ -f "$LIB_FILE" ]; then
    CURRENT_ARCHS=$(lipo -archs "$LIB_FILE" 2>/dev/null || echo "")
    CURRENT_COUNT=$(echo "$CURRENT_ARCHS" | wc -w | tr -d ' ')
    echo "当前库架构: $CURRENT_ARCHS"

    # universal binary 对单架构构建也完全兼容，直接放行
    if [ "$CURRENT_COUNT" -gt 1 ]; then
        echo "✓ 库是 universal binary，兼容所有架构"
        echo "=== 架构检测完成 ==="
        exit 0
    fi

    if [ "$CURRENT_ARCHS" = "$REQUIRED_ARCH" ]; then
        echo "✓ 架构匹配，无需更换"
        echo "=== 架构检测完成 ==="
        exit 0
    else
        echo "✗ 架构不匹配 (当前: $CURRENT_ARCHS, 需要: $REQUIRED_ARCH)，尝试更换..."
    fi
else
    echo "✗ 库文件不存在"
fi

# 选择正确架构的库文件
if [ "$REQUIRED_ARCH" = "arm64" ]; then
    SOURCE_LIB="$LIB_ARM64"
else
    SOURCE_LIB="$LIB_X86_64"
fi

# 尝试从备份恢复
if [ -f "$SOURCE_LIB" ]; then
    echo "从备份恢复: $SOURCE_LIB"
    cp "$SOURCE_LIB" "$LIB_FILE"
    echo "✓ 已替换为 $REQUIRED_ARCH 架构的库文件"
    lipo -archs "$LIB_FILE"
else
    echo "⚠ 未找到 $REQUIRED_ARCH 备份，尝试从 Rust 构建目录获取..."
    RUST_LIB_DIR="$FLUTTER_DIR/../rust-lib/target"
    if [ "$REQUIRED_ARCH" = "arm64" ]; then
        RUST_TARGET="aarch64-apple-darwin"
    else
        RUST_TARGET="x86_64-apple-darwin"
    fi
    for BUILD_TYPE in release debug; do
        RUST_LIB="$RUST_LIB_DIR/$RUST_TARGET/$BUILD_TYPE/libdart_ffi.a"
        if [ -f "$RUST_LIB" ]; then
            echo "从 Rust 构建目录恢复: $RUST_LIB"
            cp "$RUST_LIB" "$LIB_FILE"
            cp "$RUST_LIB" "$SOURCE_LIB"
            echo "✓ 已使用 Rust 构建的 $REQUIRED_ARCH 库文件"
            lipo -archs "$LIB_FILE"
            echo "=== 架构检测完成 ==="
            exit 0
        fi
    done
    echo "✗ 错误: 无法找到 $REQUIRED_ARCH 架构的库文件"
    ls -la "$LIB_DIR"/libdart_ffi.a* 2>/dev/null || echo "  (无)"
    exit 1
fi

echo "=== 架构检测完成 ==="


























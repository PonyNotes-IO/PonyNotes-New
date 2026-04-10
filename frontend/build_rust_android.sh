#!/bin/bash
# 构建 Rust 库（Release 模式）并复制到 Flutter Android 应用目录
# 使用方法: ./build_rust_android.sh

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR"
RUST_LIB_DIR="$FRONTEND_DIR/rust-lib"

# 检查 NDK 是否设置
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "错误: 未设置 ANDROID_NDK_HOME 环境变量"
    echo "请设置 ANDROID_NDK_HOME 指向 Android NDK 目录"
    exit 1
fi

# 直接设置NDK路径，避免环境变量问题
NDK_PATH="/Users/dongli/Library/Android/sdk/ndk/26.1.10909125"
NDK_TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin"

# 添加NDK工具链到PATH
export PATH="$NDK_TOOLCHAIN:$PATH"

# 构建指定架构的函数
build_arch() {
    local arch="$1"
    local target="$2"
    local compiler="$3"
    local android_dir="$4"
    
    echo "=========================================="
    echo "  构建 Rust 库 for Android (Release 模式)"
    echo "=========================================="
    echo "NDK 路径: $ANDROID_NDK_HOME"
    echo "目标架构: $arch"
    echo ""
    
    cd "$RUST_LIB_DIR"
    
    # 设置编译器环境变量
    export CC="$NDK_TOOLCHAIN/$compiler"
    export CXX="$NDK_TOOLCHAIN/${compiler/ clang/ clang++}"
    export AR="$NDK_TOOLCHAIN/llvm-ar"
    export RANLIB="$NDK_TOOLCHAIN/llvm-ranlib"
    export LINKER="$NDK_TOOLCHAIN/$compiler"
    
    # 设置额外的环境变量
    export CC_${target//-/_}="$NDK_TOOLCHAIN/$compiler"
    export CXX_${target//-/_}="$NDK_TOOLCHAIN/${compiler/ clang/ clang++}"
    export AR_${target//-/_}="$NDK_TOOLCHAIN/llvm-ar"
    export RANLIB_${target//-/_}="$NDK_TOOLCHAIN/llvm-ranlib"
    
    # 构建 Rust 库
    echo "开始构建 (这可能需要几分钟)..."
    set -e
    # 禁用 aws-lc-sys 的 getentropy 功能
    export AWS_LC_SYS_NO_GETENTROPY=1
    # 禁用 aws-lc-sys 的抖动熵功能
    export AWS_LC_SYS_NO_JITTER_ENTROPY=1
    # 禁用 aws-lc-rs 的 getentropy 功能
    export AWS_LC_RS_ENABLE_GETENTROPY=0
    # 禁用 aws-lc-rs 的所有熵功能
    export AWS_LC_RS_ENABLE_ENTROPY=0
    # 添加 CFLAGS 来禁用 getentropy 函数的使用
    export CFLAGS="-DNO_GETENTROPY -DANDROID -DHAVE_LINUX_RANDOM_H"
    export CFLAGS_${target//-/_}="-DNO_GETENTROPY -DANDROID -DHAVE_LINUX_RANDOM_H"
    export CXXFLAGS="-DNO_GETENTROPY -DANDROID -DHAVE_LINUX_RANDOM_H"
    export CXXFLAGS_${target//-/_}="-DNO_GETENTROPY -DANDROID -DHAVE_LINUX_RANDOM_H"
    # 添加 RUSTFLAGS 来禁用 getentropy 相关代码
    export RUSTFLAGS="-C link-arg=-Wl,--allow-multiple-definition -C link-arg=-ldl"
    # 禁用 cargo fmt 的执行
    export CARGO_TERM_COLOR=always
    # 使用 cargo ndk 构建，指定使用 openssl 而不是 aws-lc-sys，并禁用 s3 特性
    # 同时禁用所有依赖的默认特性，避免 aws-lc-sys 的 getentropy 问题
    cargo ndk --target "$target" --platform 29 build --release --package=dart-ffi --features "dart openssl_vendored" --no-default-features
    
    # 查找构建好的库文件
    LIB_SOURCE="$RUST_LIB_DIR/target/$target/release/libdart_ffi.so"
    
    if [ ! -f "$LIB_SOURCE" ]; then
        echo "错误: 未找到构建好的库文件: $LIB_SOURCE"
        exit 1
    fi
    
    # 创建目标目录
    mkdir -p "$android_dir"
    
    # 复制库文件
    echo "复制库文件到 Flutter Android 应用目录..."
    cp "$LIB_SOURCE" "$android_dir/"
    
    # 验证
    echo ""
    echo "✅ 构建完成！"
    echo "验证库文件:"
    ls -lh "$android_dir/libdart_ffi.so"
    file "$android_dir/libdart_ffi.so" || true
    
    echo ""
}

# 构建 arm64-v8a 架构
build_arch "arm64-v8a" "aarch64-linux-android" "aarch64-linux-android33-clang" "$FRONTEND_DIR/appflowy_flutter/android/app/src/main/jniLibs/arm64-v8a"

# 构建 armeabi-v7a 架构
build_arch "armeabi-v7a" "armv7-linux-androideabi" "armv7a-linux-androideabi33-clang" "$FRONTEND_DIR/appflowy_flutter/android/app/src/main/jniLibs/armeabi-v7a"

echo "=========================================="
echo "  所有架构构建完成！"
echo "  现在可以构建 Flutter Android 应用了！"
echo "=========================================="

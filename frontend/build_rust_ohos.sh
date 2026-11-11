#!/bin/bash
# 构建 Rust 库（Release 模式）并复制到 Flutter OHOS 应用目录
# 使用方法: ./build_rust_ohos.sh [debug|release]
#
# 环境要求:
#   - rustup target aarch64-unknown-linux-ohos 已安装
#     (rustup target add aarch64-unknown-linux-ohos)
#   - DevEco Studio 已安装（提供 OHOS native SDK）
#
# 本脚本会自动:
#   1. 定位 DevEco 自带的 OHOS native SDK（llvm + sysroot）
#   2. 临时把 dart-ffi 的 crate-type 从 staticlib 改为 cdylib（产出 .so）
#   3. cargo build --target aarch64-unknown-linux-ohos
#   4. 复制 libdart_ffi.so 到 ohos/entry/libs/arm64-v8a/
#   5. 还原 Cargo.toml

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR"
RUST_LIB_DIR="$FRONTEND_DIR/rust-lib"
APP_DIR="$FRONTEND_DIR/appflowy_flutter"
DART_FFI_CARGO="$RUST_LIB_DIR/dart-ffi/Cargo.toml"

# 构建模式
MODE="${1:-release}"
CARGO_FLAG=""
case "$MODE" in
  release) CARGO_FLAG="--release" ;;
  debug)   CARGO_FLAG="" ;;
  *) echo "用法: $0 [debug|release]"; exit 1 ;;
esac

# === 1. 定位 OHOS native SDK ===
OHOS_NATIVE="${OHOS_NATIVE_HOME:-}"
if [ -z "$OHOS_NATIVE" ]; then
  # 自动检测 DevEco 自带的 native SDK
  for cand in \
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native" \
    "$HOME/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native" \
    "$HOME/Library/Huawei/Sdk/native"; do
    if [ -d "$cand/llvm/bin" ] && [ -d "$cand/sysroot" ]; then
      OHOS_NATIVE="$cand"; break
    fi
  done
fi

if [ -z "$OHOS_NATIVE" ] || [ ! -d "$OHOS_NATIVE/llvm/bin" ]; then
  echo "错误: 未找到 OHOS native SDK"
  echo "请通过 DevEco Studio > SDK Manager 安装 'Native'，或设置 OHOS_NATIVE_HOME 环境变量"
  exit 1
fi

LLVM_BIN="$OHOS_NATIVE/llvm/bin"
TARGET="aarch64-unknown-linux-ohos"
TARGET_CC="$LLVM_BIN/aarch64-unknown-linux-ohos-clang"
TARGET_CXX="$LLVM_BIN/aarch64-unknown-linux-ohos-clang++"

if [ ! -x "$TARGET_CC" ]; then
  echo "错误: 未找到 OHOS 交叉编译器: $TARGET_CC"
  exit 1
fi

# === 2. 检查 rustup target ===
if ! rustup target list --installed 2>/dev/null | grep -q "$TARGET"; then
  echo "错误: rustup 未安装 target $TARGET"
  echo "请运行: rustup target add $TARGET"
  exit 1
fi

# === 3. 临时修改 crate-type: staticlib -> cdylib ===
# dart-ffi Cargo.toml 基线是 ["staticlib"]（产出 .a），但 OHOS 需要 .so（DynamicLibrary.open）
# 注释里 setup-crate-type task 会做这个替换；这里手动做，构建后还原
CARGO_BAK="$DART_FFI_CARGO.bak.ohos"
echo "备份 dart-ffi/Cargo.toml -> $CARGO_BAK"
cp "$DART_FFI_CARGO" "$CARGO_BAK"

# macOS sed 和 GNU sed 语法不同，用 perl 兼容
perl -i -pe 's/crate-type = \["staticlib"\]/crate-type = ["cdylib"]/' "$DART_FFI_CARGO"

if ! grep -q 'crate-type = \["cdylib"\]' "$DART_FFI_CARGO"; then
  echo "错误: crate-type 替换失败"
  cp "$CARGO_BAK" "$DART_FFI_CARGO"
  exit 1
fi
echo "crate-type 已临时改为 cdylib"

# 还原函数（trap 确保异常退出也能还原）
restore_cargo() {
  if [ -f "$CARGO_BAK" ]; then
    cp "$CARGO_BAK" "$DART_FFI_CARGO"
    rm -f "$CARGO_BAK"
    echo "dart-ffi/Cargo.toml 已还原"
  fi
}
trap restore_cargo EXIT INT TERM

# === 4. 设置交叉编译环境 ===
export CC="$TARGET_CC"
export CXX="$TARGET_CXX"
export AR="$LLVM_BIN/llvm-ar"
export RANLIB="$LLVM_BIN/llvm-ranlib"
export STRIP="$LLVM_BIN/llvm-strip"

# target-specific 变量（cargo 用 target 名转下划线）
TARGET_US="${TARGET//-/_}"
export "CC_$TARGET_US"="$TARGET_CC"
export "CXX_$TARGET_US"="$TARGET_CXX"
export "AR_$TARGET_US"="$LLVM_BIN/llvm-ar"
export "RANLIB_$TARGET_US"="$LLVM_BIN/llvm-ranlib"

# aws-lc-sys / openssl 兼容（参考 Android 脚本）
export AWS_LC_SYS_NO_GETENTROPY=1
export AWS_LC_SYS_NO_JITTER_ENTROPY=1
export AWS_LC_RS_ENABLE_GETENTROPY=0
export AWS_LC_RS_ENABLE_ENTROPY=0
# sqlite-vec.c 用了 BSD 风格的 u_int8_t/u_int16_t/u_int64_t（glibc 有，musl/OHOS 没有）
# 用宏映射成标准的 uint8_t/uint16_t/uint64_t（OHOS sysroot 有）
SQLITE_VEC_FIX="-Du_int8_t=uint8_t -Du_int16_t=uint16_t -Du_int64_t=uint64_t"
export CFLAGS="-DNO_GETENTROPY $SQLITE_VEC_FIX"
export CFLAGS_$TARGET_US="-DNO_GETENTROPY $SQLITE_VEC_FIX"
export CXXFLAGS="-DNO_GETENTROPY $SQLITE_VEC_FIX"
export CXXFLAGS_$TARGET_US="-DNO_GETENTROPY $SQLITE_VEC_FIX"

# RUSTFLAGS:
#   -C linker=<OHOS clang>  让 rustc 链接时用 OHOS 交叉编译器（自带 sysroot），
#   而不是系统的 cc（macOS ld 不认 GNU ELF 选项）
#   -Wl,--allow-multiple-definition + -ldl  参考 Android 脚本
export RUSTFLAGS="-C linker=$TARGET_CC -C link-arg=-Wl,--allow-multiple-definition -C link-arg=-ldl"
export CARGO_TERM_COLOR=always

# === 5. 构建 ===
echo ""
echo "=========================================="
echo "  构建 Rust 库 for OHOS ($MODE)"
echo "=========================================="
echo "OHOS native: $OHOS_NATIVE"
echo "Target:      $TARGET"
echo "CC:          $TARGET_CC"
echo ""

cd "$RUST_LIB_DIR"
set -e
echo "开始构建（首次可能需要几分钟编译 C 依赖如 openssl/aws-lc-sys）..."
cargo build --target "$TARGET" $CARGO_FLAG \
  --package=dart-ffi \
  --features "dart openssl_vendored" \
  --no-default-features

# === 6. 定位并复制产物 ===
LIB_SOURCE="$RUST_LIB_DIR/target/$TARGET/$MODE/libdart_ffi.so"

if [ ! -f "$LIB_SOURCE" ]; then
  echo "错误: 未找到构建产物: $LIB_SOURCE"
  echo "（crate-type 是否成功改为 cdylib？检查上方日志）"
  exit 1
fi

DEST_DIR="$APP_DIR/ohos/entry/libs/arm64-v8a"
mkdir -p "$DEST_DIR"
cp "$LIB_SOURCE" "$DEST_DIR/"

echo ""
echo "✅ 构建完成！"
echo "产物: $DEST_DIR/libdart_ffi.so"
ls -lh "$DEST_DIR/libdart_ffi.so"
file "$DEST_DIR/libdart_ffi.so" || true

echo ""
echo "=========================================="
echo "  OHOS Rust 库构建完成"
echo "  现在可以 flutter build hap 了"
echo "=========================================="

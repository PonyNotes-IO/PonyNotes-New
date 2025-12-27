#!/usr/bin/env bash
set -euo pipefail

# Build universal libdart_ffi.a for macOS (x86_64 + arm64) and place into
# frontend/appflowy_flutter/packages/appflowy_backend/macos/libdart_ffi.a
#
# Usage:
#   ./scripts/build_universal_dart_ffi.sh
#
# This script:
# 1. Ensures rust targets for x86_64-apple-darwin and aarch64-apple-darwin are installed.
# 2. Runs cargo-make build for each target (using Makefile.toml task appflowy-core-dev).
# 3. Locates the produced static libs and merges them via lipo into a universal binary.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_LIB="$FRONTEND_DIR/appflowy_flutter/packages/appflowy_backend/macos/libdart_ffi.a"
BACKUP_LIB="${OUTPUT_LIB}.backup.$(date +%s)"

REPO_ROOT="$(cd "$FRONTEND_DIR/.." && pwd)"
echo "Repo root: $REPO_ROOT"
echo "Frontend dir: $FRONTEND_DIR"
echo "Output lib: $OUTPUT_LIB"

echo "Ensuring rust targets..."
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin

build_for_target() {
  local target="$1"
  echo "Building for target: $target"
  pushd "$FRONTEND_DIR" > /dev/null
  # Use cargo make to ensure project-specific build steps are honored.
  RUST_COMPILE_TARGET="$target" cargo make --makefile Makefile.toml appflowy-core-dev
  popd > /dev/null
}

find_built_lib() {
  local target="$1"
  # Common locations to check (project-specific)
  local candidates=(
    "$FRONTEND_DIR/rust-lib/target/$target/release/libdart_ffi.a"
    "$FRONTEND_DIR/rust-lib/target/$target/debug/libdart_ffi.a"
    "$FRONTEND_DIR/target/$target/release/libdart_ffi.a"
    "$FRONTEND_DIR/target/$target/debug/libdart_ffi.a"
    "$FRONTEND_DIR/appflowy_flutter/packages/appflowy_backend/macos/libdart_ffi.a"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

echo "Building arm64 (aarch64-apple-darwin)..."
build_for_target aarch64-apple-darwin
ARM_LIB="$(find_built_lib aarch64-apple-darwin || true)"
if [[ -z "$ARM_LIB" ]]; then
  echo "ERROR: failed to find built arm64 libdart_ffi.a" >&2
  exit 2
fi
echo "Found ARM lib: $ARM_LIB"

echo "Building x86_64 (x86_64-apple-darwin)..."
build_for_target x86_64-apple-darwin
X86_LIB="$(find_built_lib x86_64-apple-darwin || true)"
if [[ -z "$X86_LIB" ]]; then
  echo "ERROR: failed to find built x86_64 libdart_ffi.a" >&2
  exit 3
fi
echo "Found x86 lib: $X86_LIB"

mkdir -p "$(dirname "$OUTPUT_LIB")"

if [[ -f "$OUTPUT_LIB" ]]; then
  echo "Backing up existing $OUTPUT_LIB -> $BACKUP_LIB"
  cp "$OUTPUT_LIB" "$BACKUP_LIB"
fi

echo "Creating universal binary..."
lipo -create "$X86_LIB" "$ARM_LIB" -output "$OUTPUT_LIB"

echo "Verifying universal binary..."
lipo -info "$OUTPUT_LIB"

echo "Universal lib created at $OUTPUT_LIB"
echo "Done."



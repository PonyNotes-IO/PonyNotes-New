#!/usr/bin/env bash

# check the cost time
start_time=$(date +%s)

# read the arguments to skip the pub get and package get
skip_pub_get=false
skip_pub_packages_get=false
verbose=false
include_packages=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    --skip-pub-get)
        skip_pub_get=true
        shift
        ;;
    --skip-pub-packages-get)
        skip_pub_packages_get=true
        shift
        ;;
    --verbose)
        verbose=true
        shift
        ;;
    --exclude-packages)
        shift
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

echo "📷 Start generating image/svg files"

# Directly use system flutter/dart command
if ! command -v flutter >/dev/null 2>&1; then
    echo "❌ flutter command not found. Install Flutter first."
    exit 1
fi
if ! command -v dart >/dev/null 2>&1; then
    echo "❌ dart command not found. Install Dart first."
    exit 1
fi
FLUTTER_CMD="flutter"
DART_CMD="dart"

# Store the current working directory
original_dir=$(pwd)

cd "$(dirname "$0")"

# Navigate to the project root
cd ../../../appflowy_flutter

rm -rf assets/flowy_icons/
mkdir -p assets/flowy_icons/
rsync -r ../resources/flowy_icons/ assets/flowy_icons/

if [ "$skip_pub_get" = false ]; then
    if [ "$verbose" = true ]; then
        $FLUTTER_CMD pub get
    else
        $FLUTTER_CMD pub get >/dev/null 2>&1
    fi
fi

if [ "$include_packages" = true ]; then
    if [ "$verbose" = true ]; then
        $FLUTTER_CMD packages pub get
    else
        $FLUTTER_CMD packages pub get >/dev/null 2>&1
    fi
fi

# Use flutter pub run instead of dart run to ensure we use Flutter's Dart SDK
if [ "$verbose" = true ]; then
    $FLUTTER_CMD pub run flowy_svg
else
    $FLUTTER_CMD pub run flowy_svg >/dev/null 2>&1
fi

# Return to the original directory
cd "$original_dir"

echo "📷 Done generating image/svg files."

# echo the cost time
end_time=$(date +%s)
cost_time=$((end_time - start_time))
echo "📷 Image/svg files generation cost $cost_time seconds."

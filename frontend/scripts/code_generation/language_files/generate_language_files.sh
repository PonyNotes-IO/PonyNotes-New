#!/usr/bin/env bash

set -e

# check the cost time
start_time=$(date +%s)

# read the arguments to skip the pub get and package get
skip_pub_get=false
skip_pub_packages_get=false
verbose=false

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

echo "🌍 Start generating language files."

# Determine flutter/dart commands (prefer FVM)
# Check if fvm exists and can actually run (not just found in PATH)
FVM_AVAILABLE=false
if command -v fvm >/dev/null 2>&1; then
    # Try to run fvm to check if it's the correct architecture
    if fvm --version >/dev/null 2>&1; then
        FVM_AVAILABLE=true
    fi
fi

if [ "$FVM_AVAILABLE" = true ]; then
    FLUTTER_CMD="fvm flutter"
    DART_CMD="fvm dart"
else
    if ! command -v flutter >/dev/null 2>&1; then
        echo "❌ flutter command not found. Install Flutter or FVM first."
        exit 1
    fi
    if ! command -v dart >/dev/null 2>&1; then
        echo "❌ dart command not found. Install Dart or FVM first."
        exit 1
    fi
    FLUTTER_CMD="flutter"
    DART_CMD="dart"
fi

# Store the current working directory
original_dir=$(pwd)

cd "$(dirname "$0")"

# Navigate to the project root
cd ../../../appflowy_flutter

# copy the resources/translations folder to
# the appflowy_flutter/assets/translation directory
rm -rf assets/translations/
mkdir -p assets/translations/
cp -f ../resources/translations/*.json assets/translations/

# the ci alwayas return a 'null check operator used on a null value' error.
# so we force to exec the below command to avoid the error.
# https://github.com/dart-lang/pub/issues/3314
if [ "$skip_pub_get" = false ]; then
    if [ "$verbose" = true ]; then
        $FLUTTER_CMD pub get
    else
       $FLUTTER_CMD pub get >/dev/null 2>&1
    fi
fi
if [ "$skip_pub_packages_get" = false ]; then
    if [ "$verbose" = true ]; then
        $FLUTTER_CMD packages pub get
    else
        $FLUTTER_CMD packages pub get >/dev/null 2>&1
    fi
fi

# Use flutter pub run instead of dart run to ensure we use Flutter's Dart SDK
if [ "$verbose" = true ]; then
    $FLUTTER_CMD pub run easy_localization:generate -S assets/translations/
    $FLUTTER_CMD pub run easy_localization:generate -f keys -o locale_keys.g.dart -S assets/translations/ -s en-US.json
else
    $FLUTTER_CMD pub run easy_localization:generate -S assets/translations/ >/dev/null 2>&1
    $FLUTTER_CMD pub run easy_localization:generate -f keys -o locale_keys.g.dart -S assets/translations/ -s en-US.json >/dev/null 2>&1
fi

echo "🌍 Done generating language files."

# Return to the original directory
cd "$original_dir"

# echo the cost time
end_time=$(date +%s)
cost_time=$((end_time - start_time))
echo "🌍 Language files generation cost $cost_time seconds."

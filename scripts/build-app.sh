#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Brian.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/Brian" "$app_dir/Contents/MacOS/Brian"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"

#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
release_bin="$root_dir/.build/release/ArkCodexDeskpet"
app_dir="$root_dir/dist/ArkCodexDeskpet.app"

cd "$root_dir"
swift build -c release
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$release_bin" "$app_dir/Contents/MacOS/ArkCodexDeskpet"
cp -R "$root_dir/Sources/ArkCodexDeskpet/pets" "$app_dir/Contents/Resources/pets"
cp "$root_dir/packaging/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
echo "Built: $app_dir"

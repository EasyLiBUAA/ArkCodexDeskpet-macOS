#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
release_bin="$root_dir/.build/release/ArkCodexDeskpet"
output_app="$root_dir/dist/ArkCodexDeskpet.app"
staging_dir="$(mktemp -d /private/tmp/ark-codex-deskpet-build.XXXXXX)"
app_dir="$staging_dir/ArkCodexDeskpet.app"
trap 'rm -rf "$staging_dir"' EXIT

cd "$root_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$release_bin" "$app_dir/Contents/MacOS/ArkCodexDeskpet"
cp -R "$root_dir/Sources/ArkCodexDeskpet/pets" "$app_dir/Contents/Resources/pets"
cp "$root_dir/packaging/Info.plist" "$app_dir/Contents/Info.plist"
xattr -cr "$app_dir"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
rm -rf "$output_app"
mkdir -p "${output_app:h}"
cp -R "$app_dir" "$output_app"
xattr -d com.apple.FinderInfo "$output_app" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$output_app" 2>/dev/null || true
codesign --verify --deep --strict "$output_app"
echo "Built: $output_app"

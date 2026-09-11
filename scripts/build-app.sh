#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
release_bin="$root_dir/.build/release/ArkCodexDeskpet"
output_app="$root_dir/dist/ArkCodexDeskpet.app"
staging_dir="$(mktemp -d /private/tmp/ark-codex-deskpet-build.XXXXXX)"
app_dir="$staging_dir/ArkCodexDeskpet.app"
iconset_dir="$staging_dir/AppIcon.iconset"
trap 'rm -rf "$staging_dir"' EXIT

cd "$root_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"
cp "$release_bin" "$app_dir/Contents/MacOS/ArkCodexDeskpet"
cp -R "$root_dir/Sources/ArkCodexDeskpet/pets" "$app_dir/Contents/Resources/pets"
# Finder and LaunchServices expect a compiled .icns resource. Generate all
# standard iconset sizes from the supplied 1024px artwork during every build.
for spec in \
  "16 icon_16x16.png" "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size="${spec%% *}"
  name="${spec#* }"
  sips -z "$size" "$size" "$root_dir/packaging/AppIcon-1024.png" --out "$iconset_dir/$name" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$root_dir/packaging/Info.plist" "$app_dir/Contents/Info.plist"
xattr -cr "$app_dir"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
rm -rf "$output_app"
mkdir -p "${output_app:h}"
cp -R "$app_dir" "$output_app"
xattr -cr "$output_app"
xattr -d com.apple.FinderInfo "$output_app" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$output_app" 2>/dev/null || true
codesign --verify --deep --strict "$output_app"
echo "Built: $output_app"

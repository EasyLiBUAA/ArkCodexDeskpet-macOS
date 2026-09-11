#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
app_path="$root_dir/dist/ArkCodexDeskpet.app"
dmg_path="$root_dir/dist/ArkCodexDeskpet-1.3.0.dmg"

if [[ ! -d "$app_path" ]]; then
  "$root_dir/scripts/build-app.sh"
fi

rm -f "$dmg_path"
hdiutil create -volname "ArkCodexDeskpet" -srcfolder "$app_path" -ov -format UDZO "$dmg_path"
echo "Built: $dmg_path"

#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
manifest="$root_dir/Sources/ArkCodexDeskpet/pets/予愿安洁莉娜/manifest.json"

jq empty "$manifest"
while IFS=$'\t' read -r state count; do
  actual=$(find "$root_dir/Sources/ArkCodexDeskpet/pets/予愿安洁莉娜/frames/$state" -maxdepth 1 -name 'frame_*.png' | wc -l | tr -d ' ')
  [[ "$actual" == "$count" ]] || { print -u2 "State $state: expected $count frames, found $actual"; exit 1; }
done < <(jq -r '.states | to_entries[] | [.key, .value.count] | @tsv' "$manifest")

print "Asset manifests and animation frame counts are valid."

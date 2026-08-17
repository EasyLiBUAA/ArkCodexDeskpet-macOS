# Ark Codex Deskpet for macOS

A native macOS menu-bar desktop pet for Codex. It plays transparent Arknights
animation frames, follows the current Codex session status, supports a pet
library, smooth drag resizing, drag locking, and mini mode.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 5.9 or later

No Python environment or third-party runtime is required.

## Run and package

```zsh
./scripts/run.sh
./scripts/build-app.sh
open dist/ArkCodexDeskpet.app
```

The packaged app is ad-hoc signed for local use. It is not notarized; macOS may
ask for confirmation the first time it is opened.

## Use

- Click the pet for its interaction animation.
- Drag the handle in the pet's lower-right corner to resize it smoothly.
- Drag anywhere else on the pet to move it. Choose `锁定位置` when you do not
  want it to move accidentally.
- Right-click the pet or use the menu-bar icon for actions and settings.
- Choose `从 PRTS 联网添加…`, search for an operator, select a result and skin,
  and wait while the app downloads and generates local animation frames.
- Choose `从本地文件夹导入…` to import an existing compatible pet package.
- The status ribbon reads `~/.codex/sessions/` only; it never writes Codex data.

An importable package is a folder containing `manifest.json` and
`frames/<state>/frame_XXXX.png`. Imported pets are validated and copied to
`~/Library/Application Support/ArkCodexDeskpet/pets`, so app upgrades do not
remove them. The original project's PRTS exporter and WebM processor can
produce this layout.

Online import connects only to the public PRTS Wiki API and asset hosts. The
generated operator frames are stored locally and are not included in this
repository.

## Attribution

See [NOTICE.md](NOTICE.md). This project references the Windows implementation
from [AstrariaX/Ark-codex-skill](https://github.com/AstrariaX/Ark-codex-skill).
Arknights assets are for personal, non-commercial use only.

# Ark Codex Deskpet for macOS

A native macOS menu-bar desktop pet for Codex. It plays transparent Arknights
animation frames, follows the current Codex session status, supports a pet
library, drag locking, scaling, and mini mode.

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
- Unlock drag from the pet menu before moving it.
- Right-click the pet or use the menu-bar icon for actions and settings.
- The status ribbon reads `~/.codex/sessions/` only; it never writes Codex data.

Add another pet by creating `Sources/ArkCodexDeskpet/pets/<name>/manifest.json` and state frame folders
that follow the included sample manifest. The original project's PRTS exporter
and WebM processor can produce this layout.

## Attribution

See [NOTICE.md](NOTICE.md). This project references the Windows implementation
from [AstrariaX/Ark-codex-skill](https://github.com/AstrariaX/Ark-codex-skill).
Arknights assets are for personal, non-commercial use only.

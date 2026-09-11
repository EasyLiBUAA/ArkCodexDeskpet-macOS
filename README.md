# Ark Codex Deskpet（macOS）

原生 Swift/AppKit 菜单栏桌宠，同时显示 Codex 与 WorkBuddy 的本地状态，支持拖动、缩放、动画切换和 PRTS 联网导入。

## 系统要求

- macOS 13 或更高版本
- Apple Silicon 或 Intel Mac
- 从源码构建时需要 Xcode Command Line Tools（Swift 5.9+）

## 直接使用 DMG

打开 `dist/ArkCodexDeskpet-1.3.0.dmg`，将应用拖入“应用程序”文件夹，然后双击启动。首次打开若提示来源确认：右键应用 →“打开”→“打开”。

应用默认在登录 macOS 后自动启动；右键桌宠或点击菜单栏闪光图标，可取消“登录时自动启动”。

## 从源码构建

```zsh
./scripts/build-app.sh
open dist/ArkCodexDeskpet.app
```

运行测试：

```zsh
swift test
./scripts/verify-assets.sh
```

构建脚本会生成 `dist/ArkCodexDeskpet.app`。如需重新制作 DMG：

```zsh
./scripts/build-dmg.sh
```

## 功能

- 点击桌宠播放互动动画；拖动桌宠移动位置；拖动右下角手柄平滑缩放。
- 右键菜单可锁定位置、显示/隐藏状态、切换动画和桌宠。
- `从 PRTS 联网添加…`：搜索干员、选择时装并生成本地动画。
- `从本地文件夹导入…`：导入含 `manifest.json` 与 `frames/<state>/frame_XXXX.png` 的桌宠包。
- Codex 状态显示阶段和当前任务摘要，例如“分析中、修改中、执行中、整理回复、已完成、待机”。WorkBuddy 仅检测应用是否运行及是否在前台，不读取聊天内容。

用户导入的桌宠保存在 `~/Library/Application Support/ArkCodexDeskpet/pets`，升级应用不会删除。

## 数据与隐私

Codex 只读取 `~/.codex/sessions/` 的本地会话事件；WorkBuddy 只使用 macOS 运行应用列表。不会上传会话、聊天或个人文件。

## 来源与授权

本项目是 macOS 独立移植版，参考了 [AstrariaX/Ark-codex-skill](https://github.com/AstrariaX/Ark-codex-skill)。应用图标使用通过 PRTS 工作流导入的干员透明帧，仅供个人、非商业使用。详见 [NOTICE.md](NOTICE.md)。

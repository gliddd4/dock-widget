# Dock Widget

Display macOS Dock in the Touch Bar and enjoy your screen in full-size every time!

This is a heavily customized fork of [Pock's dock-widget](https://github.com/pock/dock-widget), rebuilt around a calibrated dock with global hotkeys, a Raycast-style app cheat sheet, media controls, and a standalone corner-dock helper.

## Features

- **Touch Bar dock** with full badge support, folder and trash items, and multi-window support.
- **Calibrated sizing** — dock item size (38×36) and vertical offset are baked in as permanent defaults, with live calibration hotkeys to fine-tune at runtime.
- **Reliable app launching** — tapping a dock icon toggles/launches the app with a real frontmost check, and minimized apps restore correctly even under "minimize into application icon".
- **Option-hold app cheat sheet** — hold `Option` to reveal a numbered, Spotlight/Raycast-style panel of your dock apps; type to search, dimmed entries show closed apps.
- **Global hotkeys** (registered by `OptionNumberHotKeys`):
  - `Option` + `1–9` → switch to the Nth dock app (auto-flips to `Option+Shift`+number when a frontmost app like FL Studio owns those combos)
  - `Option` + `[` / `]` → shrink / grow dock icon size
  - `Option` + `Shift` + `[` / `]` → move the dock up / down
  - `Option` + `Space` → play/pause; `Option` + `←` / `→` → previous/next track
  - `Option` + `↑` / `↓` → volume up / down
- **Mouse scroll mode** (`MouseScrollController`) — press `Option+W` to warp the cursor to the center of the frontmost window, then `W`/`S` scroll up/down while `Option` is held; releasing `Option` restores the cursor.
- **Corner dock helper** (`corner-dock/`) — a small standalone menu-bar-free app: hover the bottom-right corner to reveal Trash, bottom-left for Downloads.

## Building

Open `Dock.xcworkspace` with Xcode and build the **Dock** target (CocoaPods dependencies are already vendored). `corner-dock` builds separately as a Swift Package.

## Preview

<img src="https://pock.app/_nuxt/img/pock_dock_widget.6c84647.png" height="60">

<img src="https://pock.app/_nuxt/img/pock_app_expose.122ed53.png" height="60">

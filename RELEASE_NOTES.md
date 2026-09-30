## SlideWand v1.1.0 — menu-bar app + gesture test window

### What's new

- **Menu-bar app**: SlideWand now lives in the menu bar (👋 icon) with no Dock icon. The camera preview is a window you can close — the app keeps running. The menu icon turns red if the camera is off or Accessibility is blocking keys.
- **Gesture Test window** (👋 → Open Gesture Test…): watch your live hand state, big NEXT/PREV flashes, running counters, and a timestamped event log. The fastest way to verify it's working — every trigger also presses a real arrow key.
- Fixed: the preview window drew nothing until the first camera frame arrived, so a slow camera start looked like an empty window. It now renders its HUD immediately and shows "Waiting for camera permission…" while macOS prompts.

### Install

1. Download **`SlideWand-macos.zip`** below and unzip it.
2. **Right-click `SlideWand.app` → Open** (one time only — not Apple-notarized yet, so Gatekeeper needs the manual OK; after that it opens normally). If macOS still refuses: `xattr -dr com.apple.quarantine /path/to/SlideWand.app`
3. Grant **Camera** when prompted.
4. Grant **Accessibility**: System Settings → Privacy & Security → Accessibility → add **SlideWand**. The app opens that page for you on first run.

### Gestures

| Do this | Happens |
|---|---|
| Wave hand quickly to **your right** | Next slide → |
| Wave hand quickly to **your left** | ← Previous slide |
| Hold an **open palm** still ~1 sec | Next slide → |
| Hold a **closed fist** still ~1 sec | ← Previous slide |

### Privacy

Everything runs on-device with Apple's Vision framework. The camera feed is processed in memory and never saved, uploaded, or transmitted. The app makes no network connections at all.

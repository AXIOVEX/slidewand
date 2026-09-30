## SlideWand v1.0.0 — first release

Wave your hand to change slides. No clicker, no keyboard, no standing next to the laptop.

### Install

1. Download **`SlideWand-macos.zip`** below and unzip it.
2. **Right-click `SlideWand.app` → Open** (one time only). The app isn't Apple-notarized yet, so Gatekeeper needs this manual OK on first launch — after that it opens normally with a double-click.
3. Grant **Camera** access when prompted.
4. Grant **Accessibility**: System Settings → Privacy & Security → Accessibility → add **SlideWand**. (macOS never prompts for this one — the app opens that Settings page for you on first run and shows a banner until it's granted. It starts working the moment you toggle it, no restart needed.)

Then start your slideshow (Keynote, PowerPoint, Google Slides, PDF — anything that advances with arrow keys), make sure it's the focused window, and wave.

### Gestures

| Do this | Happens |
|---|---|
| Wave hand quickly to **your right** | Next slide → |
| Wave hand quickly to **your left** | ← Previous slide |
| Hold an **open palm** still ~1 sec | Next slide → |
| Hold a **closed fist** still ~1 sec | ← Previous slide |

### Privacy

Everything runs on-device with Apple's Vision framework. The camera feed is processed in memory and never saved, uploaded, or transmitted. The app makes no network connections at all.

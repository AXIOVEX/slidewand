# SlideWand 1.3.3

## What changed
- **Mirrored camera preview.** The preview is now flipped horizontally (selfie-style), which is what the gesture math always assumed — the hand skeleton overlay and wave directions now line up with the video. Done with a display-only layer transform; the macOS 26 capture-connection mirroring call that crashed 1.3.0/1.3.1 stays removed for good.
- **Fixed a crash on quit.** The menu-bar refresh timer could fire while the app was tearing down (EXC_BAD_ACCESS in the menu tick); it is now stopped in `applicationWillTerminate`, and the camera is released on quit.
- Version 1.3.3 (build 8). Regular Dock app; still not Apple-notarized (right-click → Open on first launch).

## Install
Download `SlideWand-macos.zip` below, unzip, move `SlideWand.app` to `/Applications`, then right-click → Open (first launch only). Grant Camera when asked.

---

# SlideWand 1.3.2

## What changed
- **Fixed the launch crash (the real bug).** On macOS 26's new camera stack, setting the preview layer's `isVideoMirrored` throws an Objective-C exception, which macOS turns into an instant crash a few seconds after launch. The mirroring call is removed — the preview now shows unmirrored video, which is also the correct orientation for directional gestures.
- Kept from 1.3.1: explicit `main.swift` bootstrap and loud `[SlideWand]` startup prints when run from Terminal.
- Version 1.3.2 (build 7). Regular Dock app; still not Apple-notarized (right-click → Open on first launch).

## Install
Download `SlideWand-macos.zip` below, unzip, move `SlideWand.app` to `/Applications`, then right-click → Open (first launch only). Grant Camera when asked.

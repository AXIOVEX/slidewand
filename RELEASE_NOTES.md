# SlideWand 1.3.2

## What changed
- **Fixed the launch crash (the real bug).** On macOS 26's new camera stack, setting the preview layer's `isVideoMirrored` throws an Objective-C exception, which macOS turns into an instant crash a few seconds after launch. The mirroring call is removed — the preview now shows unmirrored video, which is also the correct orientation for directional gestures.
- Kept from 1.3.1: explicit `main.swift` bootstrap and loud `[SlideWand]` startup prints when run from Terminal.
- Version 1.3.2 (build 7). Regular Dock app; still not Apple-notarized (right-click → Open on first launch).

## Install
Download `SlideWand-macos.zip` below, unzip, move `SlideWand.app` to `/Applications`, then right-click → Open (first launch only). Grant Camera when asked.

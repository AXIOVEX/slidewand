# SlideWand 1.3.1

## What changed
- **Explicit app bootstrap** (`Sources/main.swift`): the delegate is now wired by hand instead of relying on `@main` synthesis — removes all doubt about the launch path.
- **Loud startup diagnostics**: the app now prints each startup stage to stdout (`[SlideWand] ...`), so running the binary directly in Terminal shows exactly how far launch gets. Log path and log-write success are printed too.
- Version 1.3.1 (build 6). Still a regular Dock app; still not Apple-notarized (right-click → Open on first launch).

## Install
Download `SlideWand-macos.zip` below, unzip, move `SlideWand.app` to `/Applications`, then right-click → Open (first launch only).

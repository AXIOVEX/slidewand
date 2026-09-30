import AppKit

// Explicit bootstrap (v1.3.1): wire the delegate by hand instead of relying
// on @main synthesis, so there is zero doubt the delegate is connected.
let slideWandDelegate = AppDelegate()
let slideWandApp = NSApplication.shared
slideWandApp.delegate = slideWandDelegate
print("[SlideWand] main.swift: delegate wired, entering NSApplicationMain")
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

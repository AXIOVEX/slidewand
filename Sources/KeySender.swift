import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - Arrow-key synthesis + Accessibility permission handling

enum KeySender {
    static let keyNext: CGKeyCode = 124 // right arrow
    static let keyPrev: CGKeyCode = 123 // left arrow

    /// Posts a key down/up pair to the focused app. Silently dropped by macOS
    /// unless this process is trusted for Accessibility.
    static func press(_ keyCode: CGKeyCode) {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?
            .post(tap: .cgSessionEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?
            .post(tap: .cgSessionEventTap)
    }

    static func accessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

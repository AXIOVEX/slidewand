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

    /// Shows macOS's native "would like to control this computer" prompt.
    /// Call only from explicit user action — with the prompt option the
    /// system dialogs on every call while untrusted.
    @discardableResult
    static func requestAccessibilityTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

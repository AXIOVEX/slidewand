import AppKit
import Foundation

// MARK: - Self-updater: checks GitHub releases, downloads the zip, swaps the
// .app bundle in place, and relaunches. No frameworks, no appcast.

final class Updater {
    static let shared = Updater()
    private init() {}

    private let repo = "AXIOVEX/slidewand"
    private let assetName = "SlideWand-macos.zip"
    private let checkInterval: TimeInterval = 6 * 3600

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// Silent check, at most once per `checkInterval`. Call on launch.
    func checkAutomatically() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > checkInterval else { return }
        check(interactive: false)
    }

    /// Manual check from the menu. Reports "up to date" when there's nothing new.
    ///
    /// No GitHub API, no keys: github.com 302-redirects /releases/latest to
    /// /releases/tag/<tag>, so the final URL after redirects carries the
    /// latest version. The asset is then fetched from the plain download URL.
    func check(interactive: Bool) {
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        guard let url = URL(string: "https://github.com/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("SlideWand-updater", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            var found: (version: String, url: URL)?
            if let final = response?.url,
               final.pathComponents.suffix(2).first == "tag",
               let tag = final.pathComponents.last,
               let dlURL = URL(string: "https://github.com/\(self.repo)/releases/download/\(tag)/\(self.assetName)") {
                found = (tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), dlURL)
            }
            DispatchQueue.main.async {
                if let f = found, self.isNewer(f.version, than: self.currentVersion) {
                    self.prompt(version: f.version, url: f.url)
                } else if interactive {
                    let a = NSAlert()
                    if found == nil {
                        a.messageText = "Couldn't check for updates"
                        a.informativeText = "Check your connection and try again."
                    } else {
                        a.messageText = "You're up to date"
                        a.informativeText = "SlideWand \(self.currentVersion) is the latest version."
                    }
                    a.addButton(withTitle: "OK")
                    a.runModal()
                }
            }
        }.resume()
    }

    func isNewer(_ a: String, than b: String) -> Bool {
        let ac = a.split(separator: ".").map { Int($0) ?? 0 }
        let bc = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(ac.count, bc.count) {
            let x = i < ac.count ? ac[i] : 0
            let y = i < bc.count ? bc[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func prompt(version: String, url: URL) {
        let a = NSAlert()
        a.messageText = "SlideWand \(version) is available"
        a.informativeText = "You're on \(currentVersion). Install the update now? The app will briefly relaunch."
        a.addButton(withTitle: "Update Now")
        a.addButton(withTitle: "Later")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        downloadAndInstall(from: url)
    }

    private func setStatus(_ s: String?) {
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.setTransientStatus(s)
        }
    }

    private func note(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func downloadAndInstall(from url: URL) {
        setStatus("Downloading update…")
        URLSession.shared.downloadTask(with: url) { tmpURL, _, err in
            guard let tmpURL = tmpURL, err == nil else {
                self.setStatus(nil)
                self.note("Update failed", "Couldn't download the update. Try again later.")
                return
            }
            self.setStatus("Installing update…")
            let fm = FileManager.default
            let workDir = fm.temporaryDirectory
                .appendingPathComponent("SlideWand-update-\(Int(Date().timeIntervalSince1970))")
            do {
                try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
                let zip = workDir.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmpURL, to: zip)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", zip.path, workDir.path]
                try unzip.run()
                unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else {
                    throw NSError(domain: "SlideWand", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "couldn't unzip the download"])
                }

                let newApp = workDir.appendingPathComponent("SlideWand.app")
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: newApp.path, isDirectory: &isDir), isDir.boolValue else {
                    throw NSError(domain: "SlideWand", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "download didn't contain SlideWand.app"])
                }

                // Relaunch script: runs after we quit, swaps the bundle, reopens.
                // Quarantine is stripped from our own update so the new copy just launches.
                let appPath = Bundle.main.bundlePath
                let script = workDir.appendingPathComponent("relaunch.sh")
                let scriptText = """
                    #!/bin/sh
                    sleep 1
                    APP=\(self.shellQuote(appPath))
                    NEW=\(self.shellQuote(newApp.path))
                    xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
                    if [ -w "$APP" ] || [ -w "$(dirname "$APP")" ]; then
                      rm -rf "$APP"
                      mv "$NEW" "$APP"
                      open "$APP"
                    else
                      open \(self.shellQuote(workDir.path))
                    fi
                    """
                try scriptText.write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

                let launcher = Process()
                launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
                launcher.arguments = [script.path]
                try launcher.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch {
                self.setStatus(nil)
                self.note("Update failed",
                          "Couldn't install the update (\(error.localizedDescription)). Your current version is untouched.")
            }
        }.resume()
    }
}

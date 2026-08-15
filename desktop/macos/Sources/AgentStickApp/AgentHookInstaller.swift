import AppKit
import AgentStickCore
import Foundation

/// Installs the AgentStick hook bridge into agent CLI hook configs (Claude
/// Code, Codex, WorkBuddy, CodeBuddy, Gemini, Qwen, Qoder, Factory, Cursor)
/// so task events (started / needs attention / completed) flow into the app
/// and out to the device — including sessions AgentStick did not start.
///
/// The hook command points at a stable launcher script under
/// `~/.agentstick/bin/` which resolves the current app bundle, so app updates
/// never leave stale absolute paths behind. When the app disappears, the
/// launcher strips AgentStick entries from every config and fails open.
enum AgentHookInstaller {
    private static let bundleIdentifier = "app.agentstick.mac"

    private static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentstick", isDirectory: true)
    }

    static func settingsURL(for target: AgentHookIntegrationTarget) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(target.relativePath)
    }

    /// Installs hooks for every detected agent CLI when running from a real
    /// app bundle. Safe to call on every launch: the merge is idempotent and a
    /// timestamped backup precedes any modification.
    static func installAgentHooksIfNeeded() {
        guard isBundledApp else {
            NSLog("AgentHookInstaller: not a bundled app, skipping hook install")
            return
        }

        let launcherReady: Bool
        do {
            try ensureLauncherScript()
            launcherReady = true
            clearOrphanMarker()
        } catch {
            NSLog("AgentHookInstaller: launcher setup failed, skipping hook install: \(error)")
            return
        }
        guard launcherReady else { return }

        var installedCount = 0
        for target in AgentHookRegistration.targets {
            let settingsURL = settingsURL(for: target)
            guard FileManager.default.fileExists(atPath: settingsURL.path) else { continue }
            do {
                let command = launcherPath + " --source \(target.source)"
                if try AgentHookRegistration.install(
                    command: command,
                    into: settingsURL,
                    format: target.format,
                    events: target.events
                ) {
                    installedCount += 1
                    NSLog("AgentHookInstaller: hooks installed for \(target.source) (backup created)")
                }
            } catch {
                // Fail open per target: one unreadable config must not block
                // the others or app startup.
                NSLog("AgentHookInstaller: hook install failed for \(target.source): \(error)")
            }
        }
        if installedCount == 0 {
            NSLog("AgentHookInstaller: all hook configs already up to date")
        }
    }

    static func uninstallAllHooks() {
        for target in AgentHookRegistration.targets {
            do {
                try AgentHookRegistration.uninstall(from: settingsURL(for: target))
            } catch {
                NSLog("AgentHookInstaller: hook uninstall failed for \(target.source): \(error)")
            }
        }
    }

    private static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier == bundleIdentifier
            && Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var launcherPath: String {
        supportDirectory.appendingPathComponent("bin/agentstick-bridge").path
    }

    private static func ensureLauncherScript() throws {
        let fileManager = FileManager.default
        let binDirectory = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let launcherURL = URL(fileURLWithPath: launcherPath)
        let script = launcherScript()
        let existing = try? String(contentsOf: launcherURL, encoding: .utf8)
        if existing != script {
            try script.write(to: launcherURL, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherPath)

        // Refresh the bundle-path cache so the launcher finds the current app.
        let cacheURL = binDirectory.appendingPathComponent(".app-bundle")
        try Bundle.main.bundleURL.path.write(to: cacheURL, atomically: true, encoding: .utf8)
    }

    private static func clearOrphanMarker() {
        let markerURL = supportDirectory.appendingPathComponent(".orphaned")
        try? FileManager.default.removeItem(at: markerURL)
    }

    private static func launcherScript() -> String {
        let identifier = bundleIdentifier
        let configPaths = AgentHookRegistration.targets
            .map { "'" + $0.relativePath + "'" }
            .joined(separator: ", ")
        return """
        #!/bin/zsh -f
        # AgentStick hook bridge launcher (auto-generated, do not edit)
        # -f keeps user startup files out of the hook protocol stdout.
        D="$HOME/.agentstick/bin"
        [ -f "$D/.app-bundle" ] && read -r P < "$D/.app-bundle" && [ -x "$P/Contents/Helpers/AgentStickHooks" ] && exec "$P/Contents/Helpers/AgentStickHooks" "$@"
        for P in "/Applications/AgentStick.app" "$HOME/Applications/AgentStick.app"; do
          [ -x "$P/Contents/Helpers/AgentStickHooks" ] && exec "$P/Contents/Helpers/AgentStickHooks" "$@"
        done
        P="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "\(identifier)"' 2>/dev/null | /usr/bin/head -1)"
        [ -x "$P/Contents/Helpers/AgentStickHooks" ] && exec "$P/Contents/Helpers/AgentStickHooks" "$@"

        # App not found: after a 5 minute grace period (app updates move the
        # bundle briefly), strip AgentStick entries from every config and
        # fail open.
        O="$HOME/.agentstick/.orphaned"
        now=$(/bin/date +%s)
        if [ -f "$O" ]; then
          read -r T < "$O"
          [ $(( now - T )) -ge 300 ] || exit 0
        else
          echo "$now" > "$O"
          exit 0
        fi
        /usr/bin/osascript -l JavaScript <<'JSEOF' 2>/dev/null
        ObjC.import('Foundation')
        var h = ObjC.unwrap($.NSHomeDirectory()), m = 'agentstick-bridge'
        var paths = [\(configPaths)]
        function rd(p) {
          var d = $.NSData.alloc.initWithContentsOfFile(p)
          if (!d || !d.length) return null
          return ObjC.unwrap($.NSString.alloc.initWithDataEncoding(d, $.NSUTF8StringEncoding))
        }
        function wr(p, s) {
          var o = $.NSString.alloc.initWithUTF8String(s)
          o.writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null)
        }
        function strip(s) {
          var j
          try { j = JSON.parse(s) } catch (e) { return null }
          if (!j.hooks) return null
          var changed = false
          for (var ev in j.hooks) {
            var a = j.hooks[ev]
            if (!Array.isArray(a)) continue
            // Handles both shapes: nested {hooks:[{command}]} and flat {command}.
            var f = a.filter(function(e) {
              var cmds = (e.hooks || [{ command: e.command }]).map(function(x) { return x.command || '' })
              var mine = cmds.some(function(c) { return c.indexOf(m) !== -1 })
              if (mine) changed = true
              return !mine
            })
            if (!f.length) delete j.hooks[ev]; else j.hooks[ev] = f
          }
          if (!Object.keys(j.hooks).length) delete j.hooks
          return changed ? JSON.stringify(j, null, 2) + '\\n' : null
        }
        for (var i = 0; i < paths.length; i++) {
          var p = h + '/' + paths[i]
          var s = rd(p)
          if (!s) continue
          var out = strip(s)
          if (out) wr(p, out)
        }
        JSEOF
        /bin/rm -rf "$HOME/.agentstick"
        exit 0
        """
    }
}

//
//  ClaudeCodeHookInstaller.swift
//  Claude Usage
//
//  Installs Claude Code hooks that report session activity to the app.
//
//  Each hook runs a tiny shell script that drops the hook's JSON payload (plus
//  the Claude Code folder it came from) into an events directory, which
//  ClaudeCodeActivityMonitor picks up. No network port, nothing long-running
//  inside Claude Code.
//

import Foundation

enum ClaudeCodeHookInstaller {
    /// Claude Code hook events the app listens to
    static let events = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    /// Events that take a tool matcher
    private static let toolEvents: Set<String> = ["PostToolUse"]

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude Usage", isDirectory: true)
    }

    static var eventsDirectory: URL { supportDirectory.appendingPathComponent("hook-events", isDirectory: true) }
    static var scriptURL: URL { supportDirectory.appendingPathComponent("claude-code-hook.sh") }

    struct FolderStatus: Identifiable {
        let path: String
        let name: String
        let installed: Bool
        let error: String?
        var id: String { path }
    }

    // MARK: - Folders

    /// Every Claude Code config folder on this Mac: the profile switcher's
    /// folders, any ~/.claude-*, and ~/.claude itself when it's a real folder.
    static func folders() -> [ClaudeCodeFollowService.Folder] {
        var folders = ClaudeCodeFollowService.shared.availableFolders()
        let home = Constants.ClaudePaths.homeDirectory
        let defaultFolder = home.appendingPathComponent(".claude")
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: defaultFolder.path)) == nil,
           FileManager.default.fileExists(atPath: defaultFolder.path),
           !folders.contains(where: { $0.path == defaultFolder.path }) {
            folders.insert(ClaudeCodeFollowService.Folder(path: defaultFolder.path, name: ".claude"), at: 0)
        }
        return folders
    }

    static func status() -> [FolderStatus] {
        folders().map { folder in
            do {
                let settings = try readSettings(in: folder.path)
                return FolderStatus(path: folder.path, name: folder.name, installed: containsOurHooks(settings), error: nil)
            } catch {
                return FolderStatus(path: folder.path, name: folder.name, installed: false, error: error.localizedDescription)
            }
        }
    }

    // MARK: - Install / remove

    /// Adds (or refreshes) the hooks in every folder. Folders whose
    /// settings.json can't be parsed are skipped, never overwritten.
    @discardableResult
    static func installEverywhere() -> [String] {
        do { try writeScript() } catch { return ["Couldn't write the hook script: \(error.localizedDescription)"] }
        var problems: [String] = []
        for folder in folders() {
            do {
                var settings = try readSettings(in: folder.path)
                settings = removingOurHooks(from: settings)
                var hooks = settings["hooks"] as? [String: Any] ?? [:]
                for event in events {
                    var entries = hooks[event] as? [[String: Any]] ?? []
                    var entry: [String: Any] = ["hooks": [["type": "command", "command": command(for: event, folder: folder.path)]]]
                    if toolEvents.contains(event) { entry["matcher"] = "*" }
                    entries.append(entry)
                    hooks[event] = entries
                }
                settings["hooks"] = hooks
                try writeSettings(settings, in: folder.path)
            } catch {
                problems.append("\(folder.name): \(error.localizedDescription)")
            }
        }
        return problems
    }

    static func removeEverywhere() {
        for folder in folders() {
            guard let settings = try? readSettings(in: folder.path), containsOurHooks(settings) else { continue }
            try? writeSettings(removingOurHooks(from: settings), in: folder.path)
        }
    }

    // MARK: - Helpers

    private static func command(for event: String, folder: String) -> String {
        "\(shellQuote(scriptURL.path)) \(event) \(shellQuote(folder))"
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func settingsURL(in folder: String) -> URL {
        URL(fileURLWithPath: folder).appendingPathComponent("settings.json")
    }

    private static func readSettings(in folder: String) throws -> [String: Any] {
        let url = settingsURL(in: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "settings.json isn't a JSON object"])
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any], in folder: String) throws {
        let url = settingsURL(in: folder)
        // One-time backup of the user's original file
        let backup = url.appendingPathExtension("claude-usage-backup")
        if FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        var cleaned = settings
        if (cleaned["hooks"] as? [String: Any])?.isEmpty == true { cleaned["hooks"] = nil }
        let data = try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains(scriptURL.lastPathComponent) == true
        }
    }

    private static func containsOurHooks(_ settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { ($0 as? [[String: Any]] ?? []).contains { isOurs($0) } }
    }

    private static func removingOurHooks(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks
        return settings
    }

    /// The hook: first line = Claude Code folder, then the hook's JSON from stdin.
    /// PostToolUse payloads carry whole tool inputs/outputs, so for those only
    /// the session id is kept. Written atomically (tmp + mv) so the app never
    /// reads half a file; always exits 0 so it can't disturb Claude Code.
    private static func writeScript() throws {
        let script = #"""
        #!/bin/sh
        # Claude Usage: reports Claude Code activity (keep awake, alerts).
        # Removed automatically when those features are turned off.
        dir="$HOME/Library/Application Support/Claude Usage/hook-events"
        mkdir -p "$dir" 2>/dev/null
        payload=$(cat)
        if [ "$1" = "PostToolUse" ]; then
          sid=$(printf '%s' "$payload" | head -c 4096 | tr -d '\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
          payload="{\"session_id\":\"$sid\",\"hook_event_name\":\"PostToolUse\"}"
        fi
        f="$dir/$(date +%s)-$$-$1"
        { printf '%s\n' "$2"; printf '%s' "$payload"; } > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f.json" 2>/dev/null
        exit 0

        """#
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
}

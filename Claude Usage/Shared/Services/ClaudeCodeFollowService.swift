//
//  ClaudeCodeFollowService.swift
//  Claude Usage
//
//  Detects which Claude Code config folder is currently in use so the combined
//  menu bar icon can follow it. Profile switchers (e.g. the VS Code "Claude
//  Code Profile Switcher" extension) switch accounts by repointing the
//  ~/.claude symlink at a per-account folder such as ~/.claude-work.
//

import Foundation
import Combine

final class ClaudeCodeFollowService: ObservableObject {
    static let shared = ClaudeCodeFollowService()

    /// A Claude Code config folder a profile can be linked to.
    struct Folder: Hashable, Identifiable {
        let path: String
        let name: String
        var id: String { path }
    }

    /// Folder ~/.claude currently resolves to (nil when ~/.claude is not a symlink).
    @Published private(set) var currentFolder: Folder?

    private var timer: Timer?
    private let fileManager = FileManager.default
    private var home: URL { Constants.ClaudePaths.homeDirectory }

    private init() {}

    // MARK: - Watching

    /// Polls the ~/.claude symlink (a readlink every 2s is negligible) and
    /// re-renders the menu bar when the followed profile changes.
    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.tolerance = 0.5
    }

    private func poll() {
        let folder = resolveCurrentFolder()
        rememberMatches()
        guard folder != currentFolder else { return }
        currentFolder = folder
        LoggingService.shared.log("ClaudeCodeFollow: Claude Code now uses \(folder?.path ?? "the default folder")")
        if ProfileManager.shared.multiProfileConfig.followClaudeCode {
            NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
        }
    }

    private func resolveCurrentFolder() -> Folder? {
        let link = home.appendingPathComponent(".claude").path
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: link) else { return nil }
        let resolved = URL(fileURLWithPath: target, relativeTo: home).standardizedFileURL.path
        return availableFolders().first { $0.path == resolved }
            ?? Folder(path: resolved, name: URL(fileURLWithPath: resolved).lastPathComponent)
    }

    // MARK: - Folders

    /// Folders from the VS Code profile switcher settings plus any ~/.claude-* folder.
    func availableFolders() -> [Folder] {
        var folders = switcherFolders()
        let known = Set(folders.map(\.path))
        let extra = ((try? fileManager.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0.hasPrefix(".claude-") }
            .map { home.appendingPathComponent($0).standardizedFileURL.path }
            .filter { path in
                var isDir: ObjCBool = false
                return !known.contains(path) && fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted()
            .map { Folder(path: $0, name: URL(fileURLWithPath: $0).lastPathComponent) }
        folders.append(contentsOf: extra)
        return folders
    }

    /// Profiles configured in the VS Code extension (claudeProfileSwitcher.profiles).
    private func switcherFolders() -> [Folder] {
        let settings = home.appendingPathComponent("Library/Application Support/Code/User/settings.json")
        guard let raw = try? String(contentsOf: settings, encoding: .utf8),
              let data = Self.stripJSONC(raw).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["claudeProfileSwitcher.profiles"] as? [[String: Any]] else {
            return []
        }
        return profiles.compactMap { entry in
            guard let name = entry["name"] as? String, let dir = entry["configDir"] as? String else { return nil }
            let expanded = dir.hasPrefix("~") ? home.path + dir.dropFirst() : dir
            return Folder(path: URL(fileURLWithPath: expanded).standardizedFileURL.path, name: name)
        }
    }

    /// VS Code settings are JSON with comments and trailing commas.
    private static func stripJSONC(_ text: String) -> String {
        var out = ""
        var chars = Array(text)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
            } else if c == "\"" {
                inString = true; out.append(c); i += 1
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else {
                out.append(c); i += 1
            }
        }
        chars = Array(out)
        // Drop trailing commas before } or ]
        var result = ""
        for (index, c) in chars.enumerated() {
            if c == "," {
                let rest = chars[(index + 1)...].first { !$0.isWhitespace }
                if rest == "}" || rest == "]" { continue }
            }
            result.append(c)
        }
        return result
    }

    // MARK: - Profile matching

    private var lastRememberedState = ""

    /// Saves every automatic folder → profile match as an explicit link, so the
    /// match survives renaming the profile (e.g. "Work (Claude)" → "Work").
    /// Cheap: only re-evaluated when the folder list or profiles change.
    private func rememberMatches() {
        let manager = ProfileManager.shared
        let folders = availableFolders()
        let state = folders.map(\.path).joined(separator: "|") + "#"
            + manager.profiles.map { "\($0.id)\($0.name)" }.joined(separator: "|")
            + "#" + manager.multiProfileConfig.claudeCodeFolders.description
        guard state != lastRememberedState else { return }
        lastRememberedState = state

        for folder in folders {
            let config = manager.multiProfileConfig
            guard !config.claudeCodeFolders.values.contains(folder.path),
                  let match = profile(for: folder, in: manager.profiles, config: config) else { continue }
            LoggingService.shared.log("ClaudeCodeFollow: linking \(folder.path) to profile '\(match.name)'")
            manager.setClaudeCodeFolder(folder.path, for: match.id)
        }
    }

    /// Profile linked to the folder Claude Code currently uses, if any.
    func followedProfile(in profiles: [Profile], config: MultiProfileDisplayConfig) -> Profile? {
        guard let folder = currentFolder else { return nil }
        return profile(for: folder, in: profiles, config: config)
    }

    /// Explicit link from settings first, else a guess by login email, else by name.
    func profile(for folder: Folder, in allProfiles: [Profile], config: MultiProfileDisplayConfig) -> Profile? {
        // Only profiles of a provider that syncs with Claude Code can be "in use" there
        let profiles = allProfiles.filter { $0.provider.descriptor.capabilities.cliAccountSync }
        if let linked = profiles.first(where: { config.claudeCodeFolders[$0.id.uuidString] == folder.path }) {
            return linked
        }
        let unlinked = profiles.filter { config.claudeCodeFolders[$0.id.uuidString] == nil }
        if let email = loginEmail(in: folder) {
            let matches = unlinked.filter { Self.email(fromOAuthAccountJSON: $0.oauthAccountJSON) == email }
            if matches.count == 1 { return matches[0] }
        }
        let folderKey = Self.nameKey(folder.name)
        return unlinked.first { Self.nameKey($0.name) == folderKey }
    }

    private func loginEmail(in folder: Folder) -> String? {
        let url = URL(fileURLWithPath: folder.path).appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.email(fromOAuthAccountJSON: String(data: data, encoding: .utf8), nested: true)
    }

    private static func email(fromOAuthAccountJSON json: String?, nested: Bool = false) -> String? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let account = nested ? object["oauthAccount"] as? [String: Any] : object
        return (account?["emailAddress"] as? String)?.lowercased()
    }

    /// Normalizes profile/folder names so e.g. "Werk", "work" and ".claude-work"
    /// compare equal, including common Dutch/English synonyms.
    private static func nameKey(_ name: String) -> String {
        // "Work (Claude)" → "work": drop bracketed notes and the folder prefix
        var key = name.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".claude-", with: "")
            .trimmingCharacters(in: .whitespaces)
        let synonyms: [String: String] = [
            "werk": "work", "zakelijk": "work", "business": "work", "job": "work",
            "prive": "personal", "persoonlijk": "personal", "private": "personal", "home": "personal",
        ]
        key = synonyms[key] ?? key
        return key
    }
}

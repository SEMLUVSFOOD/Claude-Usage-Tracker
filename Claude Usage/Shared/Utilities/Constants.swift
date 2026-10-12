import Foundation

/// Application-wide constants
enum Constants {
    // Claude Code paths
    enum ClaudePaths {
        /// The REAL user home directory (not a sandboxed container)
        static var homeDirectory: URL {
            if let home = ProcessInfo.processInfo.environment["HOME"] {
                return URL(fileURLWithPath: home)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        static var claudeDirectory: URL {
            if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
                return URL(fileURLWithPath: configDir)
            }
            return homeDirectory.appendingPathComponent(".claude")
        }

        static var credentialsFile: URL {
            claudeDirectory.appendingPathComponent(".credentials.json")
        }

        /// Candidate paths for Claude Code's `.claude.json` (holds `oauthAccount`).
        /// It lives at `~/.claude.json` by default, or in `$CLAUDE_CONFIG_DIR`
        /// when that is set; some setups place it inside `~/.claude/`.
        static var claudeConfigCandidates: [URL] {
            var candidates: [URL] = []
            if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
                candidates.append(URL(fileURLWithPath: configDir).appendingPathComponent(".claude.json"))
            }
            candidates.append(homeDirectory.appendingPathComponent(".claude.json"))
            candidates.append(homeDirectory.appendingPathComponent(".claude").appendingPathComponent(".claude.json"))
            return candidates
        }
    }

    // Session window (5 hours in seconds)
    static let sessionWindow: TimeInterval = 5 * 60 * 60

    // Weekly window (7 days in seconds)
    static let weeklyWindow: TimeInterval = 7 * 24 * 60 * 60

    // Weekly limit (tokens)
    static let weeklyLimit = 1_000_000

    // API Endpoints
    enum APIEndpoints {
        static let claudeBase = "https://claude.ai/api"
        /// Default ChatGPT backend base for Codex usage. Overridable per-user
        /// via `chatgpt_base_url` in `~/.codex/config.toml`.
        static let codexBase = "https://chatgpt.com/backend-api"
        static let codexTokenRefresh = "https://auth.openai.com/oauth/token"
    }

    // Window Sizes
    enum WindowSizes {
        static let settingsWindow = NSSize(width: 720, height: 750)
    }
}

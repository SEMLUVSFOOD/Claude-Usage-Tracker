# Claude Usage (personal fork)

A small macOS menu bar app that shows the usage limits of several AI accounts in one dropdown:

- **Claude** (claude.ai session or Claude Code login) — 5-hour session, weekly limits, extra usage
- **OpenAI Codex** — via the Codex CLI login (`~/.codex/auth.json`)
- **Google Antigravity** — Gemini and Claude/GPT limits, via "Sign in with Google"

One icon sits in the menu bar and shows one account; the dropdown lists all of them. Click an account in the dropdown to show it in the menu bar, or switch on **Follow Claude Code** to have the icon follow whichever Claude account the [Claude Code Profile Switcher](https://marketplace.visualstudio.com/items?itemName=sairambkrishnan.claude-code-profile-switcher) VS Code extension has selected.

Forked from [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) and stripped down to just this.

## Build and install

No Xcode needed — only the Command Line Tools (`xcode-select --install`):

```sh
scripts/build-local.sh            # builds build/local/Claude Usage.app and Claude-Usage.dmg
scripts/build-local.sh --install  # also replaces /Applications/Claude Usage.app and relaunches it
```

The script downloads Apple's Swift 6.2 toolchain into `build/local` on first run (the project uses Swift 6.2 language features). Builds are ad-hoc signed, so after installing macOS asks once to let the app read its saved logins from the keychain — choose **Always Allow**.

With Xcode, the project (`Claude Usage.xcodeproj`) builds as usual.

## Adding an account

Settings → **Accounts** → pick the provider, give it a name, then sign in on its page:

- **Claude**: sign in to claude.ai in the built-in browser, or link a Claude Code login. One Claude account can use Claude Code's default login (`⋯` → *Use Claude Code's default login*).
- **Codex**: picked up automatically from the Codex CLI, or paste credentials.
- **Google**: *Sign in with Google* uses the sign-in built into your installed Antigravity app.

Adding another provider: see [docs/ADDING_A_PROVIDER.md](docs/ADDING_A_PROVIDER.md).

## License

MIT — see [LICENSE](LICENSE).

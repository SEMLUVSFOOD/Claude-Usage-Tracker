# Adding a Usage Provider

Every provider lives behind one seam: `ProviderRegistry`. The menu bar,
dropdown, Stats page and settings fetch through the provider's
`UsageProviderService` and read facts from its `ProviderDescriptor`, so adding a
provider is an additive checklist. Reference implementations:
`Shared/Services/Providers/Codex/` (reads a CLI's auth file) and
`Shared/Services/Providers/Antigravity/` (in-app OAuth sign-in).

## Data model contract

Usage maps onto `ClaudeUsage` (percentages + reset dates):

- primary/short window → `sessionPercentage` / `sessionResetTime`
- secondary/long window → `weeklyPercentage` / `weeklyResetTime`
- set `lastUpdated = Date()` on every live fetch — the Stats history uses it to
  tell new readings from cached ones
- no token counts? set `weeklyLimit = 0` and leave the token fields at 0

## Checklist

1. **Enum case** — add to `Provider` (`Shared/Models/Provider.swift`). The raw
   value is persisted; never rename it.

2. **Folder** — `Shared/Services/Providers/<Name>/` with an auth service
   (credential discovery/refresh/persistence), an API service (tolerant
   decoding — a new server field must never fail the whole response) and a
   `<Name>UsageProvider` conforming to `UsageProviderService`.

3. **Registry entry** — `ProviderRegistry.descriptors` (display name, logo
   fallback symbol, Statuspage-compatible status URL if any, capabilities,
   sign-in pages) and `ProviderRegistry.service(for:)`.

4. **Secrets** — a credential stored on the profile needs a `Profile` field
   (encoded only under `includeSecretsKey`, like `codexCredentialsJSON`), a
   `KeychainService.ProfileSecretField` case, and the hydrate/persist lines in
   `ProfileStore`. Extend `Profile.hasUsageCredentials` / `hasAnyCredentials`.

5. **Sign-in page** — a `SettingsSection` case (title + icon, in
   `SettingsView.swift`), a view modeled on `CodexAccountView` that edits
   `ProfileManager.shared.editingProfile`, routed in `SettingsView`'s content
   switch and listed in the descriptor's `credentialSections`.

6. **Brand mark** — add a case to `ProviderBrandMark` (`PopoverContentView.swift`)
   if the provider deserves a drawn logo; otherwise its SF Symbol fallback is used.

7. **Tests** — fixture-based decode tests (missing/malformed fields) and a
   mapping test; see `CodexProviderTests`.

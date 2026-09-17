---
id: M01-S02
type: story
title: Claude limits provider
status: done
priority: P1
notion: "3a2ea0aa-87b0-8174-a6b7-f8ebd8a897ac"
github: ""
parent: "[[M01-mvp]]"
---

Read the usage limits of the user's Claude subscription and expose them to the
app as named limits, each with a percentage used and a reset time. How to
authenticate and which endpoint to read (e.g. reusing local Claude Code
credentials vs. a claude.ai session) is decided during planning.

- [x] Connects to the user's Claude subscription, reusing existing local credentials where possible
- [x] Reports every limit Claude exposes for the account (e.g. session and weekly limits) as % used
- [x] Includes each limit's reset time when the source provides one
- [x] Signed-out or failed fetches surface as a clear disconnected state, never stale numbers

## Plan

> **Precondition**: this branch is cut from `main` and the code below builds on
> S01's provider architecture — **merge PR #1 (`feat/menu-bar-usage-display`)
> into `main` before starting**. As of planning, `origin/main` (`979c3bf`) does
> not contain S01 yet.

### Approach

**Source decision (the core of this story): reuse Claude Code's local OAuth
credentials and call the same usage endpoint Claude Code's `/usage` screen
calls — `GET https://api.anthropic.com/api/oauth/usage`.** This was verified
end-to-end on this machine during planning (2026-07-18): the endpoint string
was extracted from the installed Claude Code binary
(`~/.local/share/claude/versions/2.1.214`), and a live call with the real
Keychain token returned HTTP 200 with the account's actual limits (session
15%, weekly 48%, weekly-Fable 81%). The full captured response is the fixture
below — treat it as the contract.

Alternatives rejected:

- **claude.ai browser session cookie**: requires extracting a `sessionKey`
  cookie from Safari/Chrome, fighting Cloudflare, and re-extracting on every
  session rotation. Maximally fragile, no local tooling maintains it for us.
- **`anthropic-ratelimit-unified-*` response headers on a real
  `/v1/messages` call**: reading limits would *consume* the user's usage on
  every poll. Disqualifying.
- **Estimating from local JSONL transcripts (ccusage-style)**: an estimate,
  not the account truth — misses usage from other devices and claude.ai, and
  drifts. The story says "limits Claude exposes", so read the authoritative
  number.
- **Official Admin/Usage API**: org API-key spend metering only; consumer
  subscription limits are not exposed there.

Core decisions (each with the why):

- **Read credentials by spawning `/usr/bin/security find-generic-password -s
  "Claude Code-credentials" -w`** (login Keychain; match by service only —
  the account attribute is the local username and varies per machine).
  Verified prompt-free on this machine: Claude Code maintains that item via
  the Apple-signed `security` tool, so the item's ACL/partition list admits
  it, while a direct `SecItemCopyMatching` from our dev-signed app would hit
  the partition-list password prompt — and whether "Always Allow" survives
  Claude Code rewriting the item on every token refresh is unpredictable.
  Subprocess of an Apple-signed system binary is the boring, verified path.
  Fallback when the Keychain item is missing: read
  `~/.claude/.credentials.json` (same JSON shape; used by file-based
  installs — absent on this machine, cheap to support).
- **Never refresh the OAuth token ourselves.** The refresh token rotates on
  use; consuming it out-of-band can invalidate Claude Code's stored session
  and break the user's `claude` login. Instead, re-read the Keychain on
  *every* fetch (Claude Code refreshes the token during normal use, and its
  `expiresAt` is hours-scale), and treat an expired token or a 401 as
  disconnected with an actionable message ("open Claude Code to refresh").
  This is the single most important don't in this story.
- **Turn App Sandbox off** (`ENABLE_APP_SANDBOX = NO` on the app target,
  both configurations; hardened runtime stays YES). The app's entire purpose
  is reading other local tools' credentials, spawning `/usr/bin/security`,
  and calling the network — three things the sandbox exists to stop. It is a
  personal, direct-run app with no App Store ambitions, and S03 will need to
  read `~/.codex/` files too. Rejected: keeping sandbox +
  network-client entitlement + native Keychain API (prompt fragility above,
  and the file fallback plus S03 would be dead on arrival).
- **Map the response's `limits[]` array, not the legacy window objects.**
  It is self-describing (`kind`, `percent`, `resets_at`, `scope`), carries
  scoped per-model limits generically, and is what Claude Code's own /usage
  UI reflects. Every array entry becomes a `UsageLimit` — unknown `kind`s
  are humanized, never dropped — which is what makes AC 2 ("every limit")
  future-proof. The top-level `five_hour`/`seven_day*` objects are decoded
  only as a fallback for when `limits` is missing or empty (older server
  variants). `extra_usage`/`spend` are deliberately ignored — product scope
  excludes spend tracking (see `.project/memory/product-scope.md`).
- **No UI changes, no store changes.** S01's `UsageStore` already discards a
  provider's previous limits on any thrown error (`.disconnected(message:)`,
  menu bar falls back to `—`) — AC 4's "never stale numbers" is enforced by
  existing, tested store behavior; this provider just has to throw the right
  `UsageProviderError`. The panel already renders disconnected messages,
  reset times, and hides reset rows when `resetsAt == nil`. The only
  integration point is `ProviderRegistry.defaultProviders()` (S01's designed
  swap point).
- **No child item files**: one provider module on one branch; a task split
  would add ceremony, not clarity.

Verified endpoint contract (live capture, 2026-07-18, plan-time ground truth):

- Request: `GET https://api.anthropic.com/api/oauth/usage` with
  `Authorization: Bearer <accessToken>`. Verified: works with the auth header
  alone; still send `anthropic-beta: oauth-2025-04-20` because Claude Code
  does (cheap insurance against server-side gating), plus a UA like
  `AI-usage/1.0`. 15 s timeout.
- Invalid/expired token → HTTP 401 with body
  `{"type":"error","error":{"type":"authentication_error","message":"Invalid bearer token",...}}`.
- 200 body (verbatim capture; use as the primary decode fixture):

```json
{"five_hour":{"utilization":15.0,"resets_at":"2026-07-19T03:39:59.570750+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day":{"utilization":48.0,"resets_at":"2026-07-23T14:59:59.570774+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"seven_day_cowork":null,"seven_day_omelette":null,"tangelo":null,"iguana_necktie":null,"omelette_promotional":null,"nimbus_quill":null,"cinder_cove":null,"amber_ladder":null,"extra_usage":{"is_enabled":true,"monthly_limit":null,"used_credits":40843.0,"utilization":null,"currency":"USD","decimal_places":2,"disabled_reason":null,"daily":null,"weekly":null},"limits":[{"kind":"session","group":"session","percent":15,"severity":"normal","resets_at":"2026-07-19T03:39:59.570750+00:00","scope":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":48,"severity":"normal","resets_at":"2026-07-23T14:59:59.570774+00:00","scope":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":81,"severity":"warning","resets_at":"2026-07-23T14:59:59.571131+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}],"spend":{"used":{"amount_minor":40843,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":true,"disabled_reason":null,"cap":null,"balance":null,"auto_reload":null,"disclaimer":"Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)","can_purchase_credits":false,"can_toggle":false},"member_dashboard_available":false}
```

- Keychain secret is a JSON blob (fixture with **fake** token values —
  never put a real `sk-ant-oat01/ort01` string in the repo or in logs):

```json
{"claudeAiOauth":{"accessToken":"sk-ant-oat01-FAKE","refreshToken":"sk-ant-ort01-FAKE","expiresAt":1784443682444,"refreshTokenExpiresAt":1799995682444,"scopes":["user:inference","user:profile"],"subscriptionType":"max","rateLimitTier":"default"}}
```

  `expiresAt` is a **millisecond** epoch. Only `accessToken` and `expiresAt`
  are used; ignore the rest.
- Timestamp parsing (verified in a scratch Swift run): use
  `Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(_:)` — it
  accepts both the 6-digit-fraction form above *and* fraction-less
  `…T03:39:59+00:00`/`Z` forms. `ISO8601DateFormatter` does **not** (it
  rejects whichever fractional style it isn't configured for) — don't use it.
  Unparseable → `resetsAt = nil` (the row simply shows no reset line).

New code, concretely (app target defaults to `@MainActor` isolation — same
S01 rule applies: don't fight it; async suspension points are enough):

```swift
struct ClaudeCredentials: Equatable {
    let accessToken: String
    let expiresAt: Date?      // from ms epoch; nil if absent
}

protocol ClaudeCredentialsSource {
    func load() async throws -> ClaudeCredentials  // throws UsageProviderError.notConnected
}

// Default impl: /usr/bin/security subprocess, then ~/.claude/.credentials.json.
struct KeychainClaudeCredentialsSource: ClaudeCredentialsSource { ... }

final class ClaudeUsageProvider: UsageProvider {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    let id = "claude"                 // matches the mock's id → persisted provider selection survives
    let displayName = "Claude"
    init(credentialsSource: any ClaudeCredentialsSource = KeychainClaudeCredentialsSource(),
         transport: @escaping Transport = ClaudeUsageProvider.urlSessionTransport)
    func fetchLimits() async throws -> [UsageLimit]
}
```

`fetchLimits()` flow (each failure → thrown `UsageProviderError`, messages
short enough for the 320-pt panel):

1. `credentialsSource.load()` — Keychain item missing (`security` exits
   non-zero, e.g. 44) *and* no credentials file → `.notConnected("Not signed
   in to Claude Code")`; malformed JSON → same with a parse hint.
2. Expiry gate: `expiresAt` more than 60 s in the past →
   `.notConnected("Claude Code session expired — open Claude Code to refresh
   it")`. No network call, no token refresh.
3. Request as per contract. Transport/`URLError` →
   `.fetchFailed("Network error — check your connection")`.
4. HTTP 401/403 → `.notConnected("Claude rejected the saved credentials —
   sign in to Claude Code again")`; other non-200 →
   `.fetchFailed("Claude usage service returned HTTP <code>")`.
5. Decode failure → `.fetchFailed("Unexpected response from Claude usage
   service")`.

Subprocess note for `KeychainClaudeCredentialsSource`: wrap `Process` in
`withCheckedThrowingContinuation` using `terminationHandler` (read the stdout
pipe inside the handler, resume with data + exit code) instead of
`waitUntilExit`, so the main actor is never blocked. Launch `/usr/bin/security`
by absolute path with args `["find-generic-password", "-s",
"Claude Code-credentials", "-w"]` — no shell, no PATH lookup. Never log or
print the token; error messages must not contain it.

Mapping (`ClaudeUsageResponse.toUsageLimits()`):

- Prefer `limits[]` when present and non-empty; keep server order. Per entry:
  - `usedFraction = percent / 100` clamped to `0...1` (decode `percent` as
    `Double`; it arrives as an int).
  - `resetsAt` via the verified parser.
  - id / name by `kind`: `session` → "Session"; `weekly_all` → "Weekly (all
    models)"; `weekly_scoped` → id `"weekly_scoped:<model, lowercased>"`,
    name "Weekly (<scope.model.display_name>)" (scope missing → humanized
    kind, id plain `kind`); **unknown kinds are kept**, id = `kind`, name =
    humanized kind (underscores → spaces, first letter capitalized).
- Fallback (only when `limits` is nil/empty): non-null window objects map as
  `five_hour` → ("session", "Session"), `seven_day` → ("weekly_all",
  "Weekly (all models)"), `seven_day_opus` → ("weekly_opus", "Weekly
  (Opus)"), `seven_day_sonnet` → ("weekly_sonnet", "Weekly (Sonnet)");
  `usedFraction = utilization / 100`.
- Everything else in the body (nulled experiment fields, `spend`,
  `extra_usage`, `severity`, `is_active`) is ignored — plain `Decodable`
  structs with only the needed keys already do this.

Registry swap (the whole app integration):

```swift
static func defaultProviders() -> [any UsageProvider] {
    [ClaudeUsageProvider(), MockUsageProvider.chatGPTSample]
}
```

### Files to touch

Xcode uses file-system-synchronized groups — new `.swift` files on disk are
picked up automatically; the only `project.pbxproj` edit is the sandbox
setting.

- `AI usage.xcodeproj/project.pbxproj` — flip both `ENABLE_APP_SANDBOX = YES;`
  occurrences (app target Debug + Release `buildSettings`, currently lines
  ~401/~434, the only two in the file) to `NO`. Nothing else.
- `AI usage/Providers/Claude/ClaudeCredentials.swift` — new:
  `ClaudeCredentials`, `ClaudeCredentialsSource`,
  `KeychainClaudeCredentialsSource` (security subprocess + file fallback +
  JSON parsing).
- `AI usage/Providers/Claude/ClaudeUsageResponse.swift` — new: `Decodable`
  DTOs (`limits[]` entries with `kind`/`percent`/`resets_at`/`scope`, window
  objects), reset-date parser, `toUsageLimits()` mapping.
- `AI usage/Providers/Claude/ClaudeUsageProvider.swift` — new: the provider
  per flow above + `urlSessionTransport` default.
- `AI usage/Providers/ProviderRegistry.swift` — swap the Claude mock for
  `ClaudeUsageProvider()`; keep the ChatGPT mock (S03's swap point).
- `AI usageTests/ClaudeUsageResponseTests.swift` — new: decode + mapping
  tests over the captured fixture (embed the JSON as a string constant).
- `AI usageTests/ClaudeUsageProviderTests.swift` — new: provider flow tests
  with stub credentials source + stub transport; credentials JSON parsing
  tests (fake tokens only).
- `README.md` — Getting started: replace the "sample data" sentence (Claude
  is now real, read from the local Claude Code sign-in; ChatGPT still
  sample until S03; first launch requires being signed in to Claude Code).
  How-it-works Mermaid: Claude provider now reads Keychain credentials and
  calls the usage endpoint — e.g. `CP --> KC[(Claude Code keychain
  credentials)]` and `CP --> CA[(api.anthropic.com oauth usage)]` replacing
  the bare `CP --> CA` edge. AGENTS.md requires the diagram update in the
  same PR.
- Do **not** touch: `UsageStore.swift`, `Models/`, `Views/`,
  `MockUsageProvider.swift` (the `.claudeSample` factory stays for tests),
  existing S01 tests, `AI usageUITests/`.

### Steps

Environment note (from S01, still true): `xcode-select` points at
CommandLineTools, so prefix every `xcodebuild` with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Scheme:
`AI usage`. Build:
`DEVELOPER_DIR=… xcodebuild -project "AI usage.xcodeproj" -scheme "AI usage" -configuration Debug build`;
tests append `-destination 'platform=macOS' test -only-testing:"AI usageTests"`.

1. **Sandbox off** — the two-line pbxproj edit. Verify: build succeeds and
   `codesign -d --entitlements :- "<BUILT_PRODUCTS_DIR>/AI usage.app"` no
   longer lists `com.apple.security.app-sandbox` (get the path from
   `-showBuildSettings | grep ' BUILT_PRODUCTS_DIR'`).
2. **Credentials layer** — `ClaudeCredentials.swift` per spec (subprocess via
   continuation, file fallback, ms-epoch `expiresAt`, `notConnected` errors).
   Verify: builds; credential JSON parsing covered in step 5 tests.
3. **DTOs + mapping** — `ClaudeUsageResponse.swift` per mapping spec,
   including the verified `ISO8601FormatStyle` parser. Verify: builds.
4. **Provider** — `ClaudeUsageProvider.swift` per the 5-step flow, injectable
   transport, default `URLSession.shared`-backed transport (cast response to
   `HTTPURLResponse`, else `fetchFailed`). Verify: builds.
5. **Unit tests** — the two new test files (list in Test plan). Same S01
   gotchas: test target is not MainActor-default → annotate suites
   `@MainActor`; stubs make everything deterministic, zero network. Verify:
   full `AI usageTests` suite green (S01 tests must stay green — store
   contract unchanged).
6. **Registry swap** — `ProviderRegistry` change. Verify: build + run the
   app (`open` the built product): panel's Claude tab shows the real
   session/weekly limits with reset times; numbers match running `claude`
   → `/usage` in a terminal; ChatGPT tab still shows "(sample)" data.
7. **README** — Getting started sentence + Mermaid edge changes. Verify:
   diagram renders (mermaid syntax valid), text matches actual behavior.

### Test plan

Automated (Swift Testing, `AI usageTests` target, no network, fake tokens
only), mapped to the acceptance criteria:

- **AC 1 (connects reusing local credentials)**:
  - Credentials parsing: keychain-blob fixture → `accessToken` extracted,
    `expiresAt` ms epoch → correct `Date`; missing `claudeAiOauth` key or
    garbage JSON → `notConnected`.
  - Provider uses the source: stub source returning valid creds + stub
    transport asserting the `Authorization: Bearer sk-ant-oat01-FAKE` header
    and URL `api.anthropic.com/api/oauth/usage` → limits returned.
  - Expired creds (`expiresAt` in the past) → `notConnected` **and** the
    transport stub was never called (no doomed network round-trips, no
    refresh attempts).
- **AC 2 (every limit as % used)**:
  - Captured-fixture decode → exactly 3 limits, in server order, ids
    `["session", "weekly_all", "weekly_scoped:fable"]`, names `["Session",
    "Weekly (all models)", "Weekly (Fable)"]`, fractions `[0.15, 0.48,
    0.81]`.
  - Unknown-kind fixture (e.g. `"kind":"monthly_special","percent":5`) →
    kept, name "Monthly special" → future limits can't be silently dropped.
  - `limits: []` / `limits` absent with non-null `five_hour`/`seven_day` →
    window fallback produces "Session"/"Weekly (all models)" from
    `utilization`.
- **AC 3 (reset times when provided)**:
  - Reset parser: the two verbatim capture timestamps parse to the correct
    instants; fraction-less `…+00:00` and `…Z` variants parse; garbage →
    `nil` (limit still emitted, `resetsAt == nil`).
- **AC 4 (disconnected, never stale)**:
  - Transport returning 401 (with the captured error body) → `notConnected`;
    500 → `fetchFailed`; thrown `URLError(.notConnectedToInternet)` →
    `fetchFailed`; undecodable 200 body → `fetchFailed`.
  - Store integration (one test, reusing S01 patterns): a `UsageStore` whose
    Claude provider first succeeds then throws ends `.disconnected` with the
    prior limits gone and `menuBarText == "—"` — proving thrown errors can
    never leave stale numbers.

Manual smoke (Codex runs; user confirms at review — machine has live
credentials):

- Launch the built app → Claude tab shows real limits; cross-check numbers
  and reset times against `claude` → `/usage`.
- Select the Claude weekly limit → menu bar shows its percentage.
- Turn Wi-Fi off, press the panel's Refresh → Claude tab shows the network
  disconnected message, menu bar shows `—` (AC 4 live); Wi-Fi back on,
  Refresh → numbers return.
- Do **not** test the signed-out path by deleting the real Keychain item —
  that would sign the user out of Claude Code. The unit tests cover it.

### Risks / open questions

- **Undocumented endpoint**: `api/oauth/usage` is Claude Code's internal
  surface, not a public contract; a breaking change would surface as decode
  failures. Mitigated: tolerant decoding (only needed keys), `limits[]` +
  window fallback, and the store's disconnected state — the app degrades to
  "disconnected", never to wrong numbers. Re-capturing the fixture is the
  repair path.
- **Token staleness**: if the user stops using Claude Code for long enough,
  `expiresAt` passes and the app shows "session expired" until they open
  Claude Code again. Accepted v1 limitation; the alternative (running the
  refresh flow ourselves) risks invalidating Claude Code's rotating refresh
  token and is explicitly rejected.
- **Keychain ACL drift**: if a future Claude Code version stores credentials
  differently (different service name, native Keychain writes with a locked
  ACL), the `security` read fails → clean disconnected state, revisit then.
- **Persisted selection migration**: a user who had the mock's `weekly` /
  `weekly-opus` limit selected will see `—` in the menu bar until they
  re-pick (real ids are `weekly_all` / `weekly_scoped:fable`; `session`
  carries over). One-time, self-healing via the panel; a migration shim was
  rejected as ceremony. Auto-select only fires when no selection exists.
  Approved by the user 2026-07-18.
- **Extra-usage credits are ignored** (product scope excludes spend). If the
  user wants the credit balance surfaced later, that's a new story.
- **Sandbox removal** is a deliberate posture change for a personal
  local-credentials app — approved by the user 2026-07-18 (needed to make the
  provider work; S03 will rely on it too). Reviewer: treat as settled, do not
  flag.

### Codex handoff

Branch: `feat/claude-limits-provider` (cut from `main` **after** PR #1 is
merged).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M01-S02-claude-limits-provider.md on branch feat/claude-limits-provider."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox keeps
`.git` read-only, so `git switch`/`git commit` fail without it — see
`.project/memory/codex-sandbox-git.md`.)

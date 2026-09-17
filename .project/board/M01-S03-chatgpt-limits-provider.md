---
id: M01-S03
type: story
title: ChatGPT limits provider
status: done
priority: P1
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aY6w"
github: "https://github.com/sebastian-suarez/ai-usage/issues/5"
---

Read the usage limits of the user's ChatGPT subscription and expose them to the
app in the same shape as the Claude provider: named limits with percentage used
and reset time. ChatGPT has no official usage-limits API for consumer
subscriptions, so planning must pick the most reliable source (e.g. reusing
local Codex CLI credentials or a chatgpt.com session).

- [x] Connects to the user's ChatGPT subscription account
- [x] Reports the account's usage limits as % used
- [x] Includes each limit's reset time when available
- [x] Signed-out or failed fetches surface as a clear disconnected state, never stale numbers

## Plan

> **Precondition**: cut `feat/chatgpt-limits-provider` from `main` at or after
> `7fc58be` (S02 merged — the Claude provider files this plan mirrors are in
> the tree). This story follows S02's architecture file for file; when in
> doubt, open `AI usage/Providers/Claude/` and copy the pattern.

### Approach

**Source decision (the core of this story): reuse Codex CLI's local ChatGPT
OAuth credentials (`~/.codex/auth.json`) and call the same usage endpoint the
Codex CLI itself uses — `GET https://chatgpt.com/backend-api/wham/usage`.**
This was verified end-to-end on this machine during planning (2026-07-18):
the endpoint paths were extracted from the installed codex-cli 0.144.6 native
binary (the npm package's `vendor/aarch64-apple-darwin/bin/codex` embeds the
path pair `/wham/usage` ↔ `/api/codex/usage`; the `/wham/*` form belongs to
the `https://chatgpt.com/backend-api` base that ChatGPT-token auth uses), and
a live call with the real local access token returned HTTP 200 with the
account's actual limits (weekly 6%, "GPT-5.3-Codex-Spark" 0%). A bad token
returned HTTP 401. The full captured response (identifiers faked) is the
fixture below — treat it as the contract.

ChatGPT has no official consumer usage-limits API; the subscription exposes
its limits through the Codex surface — the plan's rolling windows (weekly
here; 5-hour + weekly on other plans) plus named per-model limits. That is
what this provider reports. Chat-side quotas that the mock invented (e.g.
"Deep research") have no credential-safe source and are simply not part of
the real provider.

Alternatives rejected:

- **chatgpt.com browser session cookie**: extracting `__Secure-next-auth`
  session cookies from Safari/Chrome, fighting Cloudflare, re-extracting on
  every rotation. Maximally fragile, no local tooling maintains it for us —
  same rejection as S02's claude.ai-cookie option.
- **Rate-limit fields on a real `/backend-api/codex/responses` turn** (how
  the Codex TUI gets mid-session snapshots): reading limits would *consume*
  the user's model quota on every poll. Disqualifying — same rule as S02.
- **platform.openai.com usage/costs APIs**: API-key org billing metering,
  not consumer subscription limits; the user is signed in with ChatGPT
  OAuth, not an API key. Mirror of S02's rejected Admin API.
- **Parsing Codex's local state** (`~/.codex/*.sqlite`, session logs): a
  stale local estimate, not the account truth; misses usage from other
  devices. Rejected like S02's transcript-estimation option.
- **Refreshing the OAuth token ourselves** (`auth.openai.com` token
  endpoint): the refresh token rotates; consuming it out-of-band can
  invalidate Codex CLI's stored session and break the user's `codex` login.
  Never do this — the single most important don't, carried over from S02.

Core decisions (each with the why):

- **Read `~/.codex/auth.json` fresh on every fetch** (plain file read — no
  Keychain involved for Codex; App Sandbox is already off per
  `.project/memory/app-sandbox-disabled.md`, which anticipated exactly this
  read — settled, do not revisit). Codex refreshes the file during normal
  use; its access token is a 10-day JWT, so staleness is rare.
- **Expiry gate via the JWT `exp` claim.** Unlike Claude's credentials JSON,
  `auth.json` has no explicit expiry field, but `tokens.access_token` is a
  JWT whose payload carries `exp` (epoch **seconds**; verified by decoding
  the real token: issued 2026-07-18, expires 2026-07-28). Base64url-decode
  the middle segment best-effort; if it parses and `exp` is more than 60 s
  past → `.notConnected` without a network call. If the JWT doesn't parse,
  proceed — the server's 401 is the authority. Never log token contents.
- **Auth-mode handling**: `auth_mode: "chatgpt"` with a non-empty
  `tokens.access_token` is the supported path. If `tokens` is null/missing
  or the access token is empty: when `OPENAI_API_KEY` is set (or
  `auth_mode` is `"apikey"`) → `.notConnected("Codex is signed in with an
  API key — sign in with ChatGPT to see plan limits")`; otherwise →
  `.notConnected("Not signed in to Codex")`. File missing entirely → the
  same "Not signed in to Codex".
- **Send the headers Codex sends** on the GET: `Authorization: Bearer
  <accessToken>`, plus `ChatGPT-Account-Id: <tokens.account_id>` when
  present and `originator: codex_cli_rs` (binary-verified header names).
  Live probe confirmed the auth header alone already gets a 200 today, so
  these two are cheap insurance against future server-side gating — the
  same reasoning as S02 sending `anthropic-beta`. UA `AI-usage/1.0`,
  `Accept: application/json`, 15 s timeout.
- **Name windows by duration, not position.** On this account the *primary*
  window is the weekly one (`limit_window_seconds: 604800`) and there is no
  secondary; on Plus/Pro-style plans a 5-hour window exists too. So
  position ≠ meaning; derive names from `limit_window_seconds` (<24 h →
  "Session (Nh)", 7 d → "Weekly", 30/31 d → "Monthly", other whole days →
  "N-day", absent → positional fallback). Named entries in
  `additional_rate_limits[]` keep their server `limit_name` verbatim and
  are **never dropped** — that is what makes AC 2 future-proof, mirroring
  S02's unknown-`kind` rule.
- **Ignore `credits`, `spend_control`, `promo`,
  `rate_limit_reset_credits`, `plan_type`** — product scope excludes
  spend/credits (`.project/memory/product-scope.md`); plain `Decodable`
  structs with only the needed keys drop the rest for free.
- **No UI changes, no store changes.** `UsageStore` already discards a
  provider's previous limits on any thrown error → AC 4's "never stale
  numbers" is enforced by existing, tested behavior; this provider just has
  to throw the right `UsageProviderError`. The only integration point is
  `ProviderRegistry.defaultProviders()` (the designed swap point). Provider
  `id` stays `"chatgpt"` — matches the mock, so persisted provider
  selection survives.
- **No child item files**: one provider module on one branch, same call as
  S02 — a task split would add ceremony, not clarity.

### Verified endpoint contract (live capture, 2026-07-18, plan-time ground truth)

- Request: `GET https://chatgpt.com/backend-api/wham/usage` with
  `Authorization: Bearer <accessToken>`; optionally `ChatGPT-Account-Id`,
  `originator: codex_cli_rs`, `User-Agent: AI-usage/1.0`. Verified: 200
  with the auth header + a generic UA alone; 200 with the full header set.
- Invalid token → HTTP 401, body
  `{"error":{"message":"Incorrect API key provided: …","type":"invalid_request_error",…}}`.
  Missing auth header → HTTP 401, body `{"detail":"Unauthorized"}`. Treat
  any 401/403 as disconnected; never parse these bodies.
- 200 body (verbatim capture except `user_id`/`account_id`/`email`, which
  are faked; use as the primary decode fixture):

```json
{
  "user_id": "user-FAKE0000000000000000FAKE",
  "account_id": "user-FAKE0000000000000000FAKE",
  "email": "user@example.com",
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 6,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 589104,
      "reset_at": 1785024392
    },
    "secondary_window": null
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": [
    {
      "limit_name": "GPT-5.3-Codex-Spark",
      "metered_feature": "codex_bengalfox",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 604800,
          "reset_at": 1785040089
        },
        "secondary_window": null
      }
    }
  ],
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0",
    "approx_local_messages": [0, 0],
    "approx_cloud_messages": [0, 0]
  },
  "spend_control": { "reached": false, "individual_limit": null },
  "rate_limit_reached_type": null,
  "promo": null,
  "rate_limit_reset_credits": {
    "available_count": 1,
    "applicable_available_count": 0
  }
}
```

- **`reset_at` is an epoch in SECONDS** (1785024392 → 2026-07-26T00:06:32Z)
  — not milliseconds (Claude's `expiresAt` was ms; don't copy that), and
  not an ISO string (no ISO8601 parsing anywhere in this provider).
  `used_percent` arrives as an integer — decode as `Double`.
- `~/.codex/auth.json` shape (fixture with **fake** values — never put a
  real token, account id, or email in the repo, the plan, or logs):

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDAsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X3BsYW5fdHlwZSI6InByb2xpdGUiLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LUZBS0UifX0.FAKESIG",
    "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDAsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X3BsYW5fdHlwZSI6InByb2xpdGUiLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LUZBS0UifX0.FAKESIG",
    "refresh_token": "FAKE-REFRESH",
    "account_id": "acct-FAKE"
  },
  "last_refresh": "2026-07-19T02:02:49.553909Z"
}
```

  Only `tokens.access_token` and `tokens.account_id` are consumed (plus the
  presence of `OPENAI_API_KEY`/`auth_mode` for the API-key message);
  `last_refresh` is **not** an expiry — ignore it. An expired-JWT test
  fixture: `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MDAwMDAwMDB9.FAKESIG`
  (`exp` 1600000000 = 2020). JWT decode rule: split on `.`, take segment 1,
  translate `-`→`+` and `_`→`/`, pad with `=` to a multiple of 4,
  `Data(base64Encoded:)`, JSON-decode `{"exp": Double}`. Any failure →
  treat as "no expiry known" and proceed to the network.

New code, concretely (app target defaults to `@MainActor` isolation — same
rule as S01/S02: don't fight it; async suspension points are enough):

```swift
struct CodexCredentials: Equatable {
    let accessToken: String
    let accountId: String?
    let expiresAt: Date?      // from the JWT exp claim (seconds); nil if undecodable
}

protocol CodexCredentialsSource {
    func load() async throws -> CodexCredentials  // throws UsageProviderError.notConnected
}

// Default impl: reads ~/.codex/auth.json; URL injectable for tests.
struct CodexAuthFileCredentialsSource: CodexCredentialsSource {
    init(authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/auth.json"))
    static func parseCredentials(_ data: Data) throws -> CodexCredentials
    static func expiry(fromJWT token: String) -> Date?   // best-effort exp claim
}

final class ChatGPTUsageProvider: UsageProvider {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    let id = "chatgpt"            // matches the mock's id → persisted provider selection survives
    let displayName = "ChatGPT"
    init(credentialsSource: any CodexCredentialsSource = CodexAuthFileCredentialsSource(),
         transport: @escaping Transport = ChatGPTUsageProvider.urlSessionTransport)
    func fetchLimits() async throws -> [UsageLimit]
}
```

`fetchLimits()` flow — mirror `ClaudeUsageProvider.fetchLimits()` step for
step; each failure throws `UsageProviderError` with messages short enough
for the 320-pt panel:

1. `credentialsSource.load()` — file missing → `.notConnected("Not signed
   in to Codex")`; API-key-only sign-in → `.notConnected("Codex is signed
   in with an API key — sign in with ChatGPT to see plan limits")`;
   malformed JSON → `.notConnected("Codex credentials are malformed — sign
   in to Codex again")`.
2. Expiry gate: `expiresAt` more than 60 s in the past →
   `.notConnected("Codex session expired — run codex to refresh it")`. No
   network call, no token refresh, ever.
3. Request per contract (headers above, 15 s timeout). Transport/`URLError`
   → `.fetchFailed("Network error — check your connection")`.
4. HTTP 401/403 → `.notConnected("ChatGPT rejected the saved credentials —
   sign in to Codex again")`; other non-200 → `.fetchFailed("ChatGPT usage
   service returned HTTP <code>")`.
5. Decode failure, or a decoded body where `rate_limit`,
   `code_review_rate_limit`, `additional_rate_limits`, and `plan_type` are
   all nil (`hasRecognizedPayload == false`, mirroring S02's guard) →
   `.fetchFailed("Unexpected response from ChatGPT usage service")`.

Mapping (`ChatGPTUsageResponse.toUsageLimits(now: Date = .now)` — `now` is
a parameter so the `reset_after_seconds` fallback is testable):

- DTOs (`Decodable`, snake_case via explicit `CodingKeys`, only these
  keys): top level `plan_type: String?`, `rate_limit: RateLimit?`,
  `code_review_rate_limit: RateLimit?`, `additional_rate_limits:
  [NamedRateLimit]?`; `RateLimit` = `primary_window: Window?`,
  `secondary_window: Window?`; `Window` = `used_percent: Double`,
  `limit_window_seconds: Double?`, `reset_after_seconds: Double?`,
  `reset_at: Double?`; `NamedRateLimit` = `limit_name: String?`,
  `metered_feature: String?`, `rate_limit: RateLimit?`.
- Emission order (stable, server order within the array): main
  `rate_limit` windows, then `code_review_rate_limit` windows, then each
  `additional_rate_limits[]` entry's windows. Per window:
  - `usedFraction = used_percent / 100` clamped to `0...1`.
  - `resetsAt`: `reset_at` present → `Date(timeIntervalSince1970:
    reset_at)`; else `reset_after_seconds` present → `now +
    reset_after_seconds`; else `nil` (row shows no reset line).
  - id / name:
    - main primary → id `"primary"`, main secondary → id `"secondary"`;
      name = duration name of `limit_window_seconds`: `<= 0`/absent →
      "Primary limit"/"Secondary limit"; `< 86400` → `"Session (Nh)"`
      with N = seconds/3600 rounded (18000 → "Session (5h)"); else days =
      seconds/86400 rounded: 1 → "Daily", 7 → "Weekly", 30 or 31 →
      "Monthly", other → `"N-day"`. (Captured fixture: primary 604800 →
      "Weekly".)
    - code review → id `"code_review"`, name "Code review"; its secondary
      window → id `"code_review:secondary"`, name "Code review
      (secondary)".
    - additional entry at index i → id prefix `"feature:" + key` where
      key = `metered_feature` if non-empty, else `limit_name` lowercased
      with spaces → `-`, else `"\(i)"`; primary id = prefix, secondary id
      = prefix + `":secondary"`. Name = `limit_name` verbatim if
      non-empty, else `metered_feature` humanized (underscores → spaces,
      first letter capitalized), else `"Limit \(i + 1)"`; secondary
      window appends " (secondary)". Captured fixture → id
      `"feature:codex_bengalfox"`, name "GPT-5.3-Codex-Spark".
  - `allowed`/`limit_reached` and everything else are ignored.

Registry swap (the whole app integration):

```swift
static func defaultProviders() -> [any UsageProvider] {
    [ClaudeUsageProvider(), ChatGPTUsageProvider()]
}
```

### Files to touch

Xcode uses file-system-synchronized groups — new `.swift` files on disk are
picked up automatically. **No `project.pbxproj` edit at all this time** (the
sandbox is already off from S02).

- `AI usage/Providers/ChatGPT/CodexCredentials.swift` — new:
  `CodexCredentials`, `CodexCredentialsSource`,
  `CodexAuthFileCredentialsSource` (auth.json read + parse + JWT-exp
  decode).
- `AI usage/Providers/ChatGPT/ChatGPTUsageResponse.swift` — new:
  `Decodable` DTOs per mapping spec, duration-based window naming,
  `toUsageLimits(now:)`.
- `AI usage/Providers/ChatGPT/ChatGPTUsageProvider.swift` — new: the
  provider per the 5-step flow + `urlSessionTransport` default (copy the
  Claude one; its non-HTTP-response guard message says "ChatGPT").
- `AI usage/Providers/ProviderRegistry.swift` — swap
  `MockUsageProvider.chatGPTSample` for `ChatGPTUsageProvider()`. After
  this, `defaultProviders()` contains no mocks; `MockUsageProvider` itself
  stays (tests use it).
- `AI usageTests/ChatGPTUsageResponseTests.swift` — new: decode + mapping
  tests over the captured fixture (embed the JSON as a string constant).
- `AI usageTests/ChatGPTUsageProviderTests.swift` — new: provider flow
  tests with stub credentials source + stub transport; auth.json parsing
  and JWT-exp tests (fake tokens only).
- `README.md` — Getting started: Claude *and* ChatGPT are now read from
  local sign-ins; require Codex CLI signed in with ChatGPT on this Mac;
  delete the "ChatGPT still displays … sample data" sentence. How-it-works
  Mermaid: replace `GP --> GA[(ChatGPT<br/>subscription)]` with
  `GP --> AJ[(~/.codex/auth.json<br/>Codex CLI sign-in)]` and
  `GP --> CG[(chatgpt.com<br/>backend-api usage)]`. AGENTS.md requires the
  diagram update in the same PR.
- Do **not** touch: `UsageStore.swift`, `Models/`, `Views/`,
  `MockUsageProvider.swift`, `Providers/Claude/*`, existing tests,
  `AI usageUITests/`, `project.pbxproj`.

### Steps

Environment note (from S01/S02, still true): `xcode-select` points at
CommandLineTools, so prefix every `xcodebuild` with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Scheme:
`AI usage`. Build:
`DEVELOPER_DIR=… xcodebuild -project "AI usage.xcodeproj" -scheme "AI usage" -configuration Debug build`;
tests append `-destination 'platform=macOS' test -only-testing:"AI usageTests"`.

1. **Credentials layer** — `CodexCredentials.swift` per spec (auth.json
   parse, auth-mode/API-key handling, best-effort JWT `exp`). Verify:
   builds; parsing behavior covered by step-4 tests.
2. **DTOs + mapping** — `ChatGPTUsageResponse.swift` per mapping spec
   (duration naming, epoch-seconds resets, `hasRecognizedPayload`).
   Verify: builds.
3. **Provider** — `ChatGPTUsageProvider.swift` per the 5-step flow,
   injectable transport, default `URLSession.shared`-backed transport.
   Verify: builds.
4. **Unit tests** — the two new test files (list in Test plan). Same
   gotchas as S01/S02: test target is *not* MainActor-default → annotate
   suites `@MainActor`; stubs make everything deterministic, zero network,
   fake tokens only. Verify: full `AI usageTests` suite green (S01 + S02
   tests must stay green — store and Claude contracts unchanged).
5. **Registry swap** — `ProviderRegistry` change. Verify: build + run the
   app (`open` the built product): ChatGPT tab shows the real weekly limit
   (~6% at plan time) plus "GPT-5.3-Codex-Spark", with reset times, no
   "(sample)" label anywhere; numbers match `codex` → `/status` in a
   terminal; Claude tab unaffected.
6. **README** — Getting started text + Mermaid edge changes. Verify:
   mermaid syntax renders; text matches actual behavior (both providers
   real, both local sign-ins required for live numbers).

### Test plan

Automated (Swift Testing, `AI usageTests` target, `@MainActor` suites, no
network, fake tokens only), mapped to the acceptance criteria:

- **AC 1 (connects to the ChatGPT subscription account)**:
  - auth.json parsing: the fake fixture above → `accessToken` extracted,
    `accountId == "acct-FAKE"`, `expiresAt == Date(timeIntervalSince1970:
    4102444800)`; `tokens` null with `"OPENAI_API_KEY": "sk-FAKE"` → the
    API-key `notConnected` message; garbage JSON → malformed
    `notConnected`; missing file (source pointed at an empty temp dir) →
    "Not signed in to Codex".
  - JWT decode: valid fake JWT → correct `Date`; not-a-JWT string →
    `expiresAt == nil` (and the provider then proceeds to the transport).
  - Provider uses the source: stub source returning valid creds + stub
    transport asserting URL ==
    `https://chatgpt.com/backend-api/wham/usage`, header `Authorization:
    Bearer <fake>`, header `ChatGPT-Account-Id: acct-FAKE` → limits
    returned. Nil `accountId` → header absent.
  - Expired creds (the `exp: 1600000000` fixture) → `notConnected` **and**
    the transport stub was never called (no doomed round-trips, no refresh
    attempts).
- **AC 2 (every limit as % used)**:
  - Captured-fixture decode → exactly 2 limits, in order: ids
    `["primary", "feature:codex_bengalfox"]`, names `["Weekly",
    "GPT-5.3-Codex-Spark"]`, fractions `[0.06, 0.0]`.
  - Synthetic Plus-shaped fixture (primary `limit_window_seconds: 18000`,
    `used_percent: 45`; secondary `604800`/`72`) → `[("primary",
    "Session (5h)", 0.45), ("secondary", "Weekly", 0.72)]` — position
    independence of naming.
  - Odd window durations: `259200` → "3-day"; `limit_window_seconds`
    absent → "Primary limit". `used_percent: 250` → clamped to `1.0`.
  - Non-null `code_review_rate_limit` → a "Code review" limit is emitted;
    named entry with empty `limit_name` but `metered_feature:
    "codex_foo_bar"` → name "Codex foo bar" — nothing the server sends is
    silently dropped.
  - All four payload sections nil → `hasRecognizedPayload == false` (the
    provider turns this into `fetchFailed`); recognized payload with zero
    windows → `[]` (panel's existing "No usage limits are available"
    state).
- **AC 3 (reset times when available)**:
  - `reset_at: 1785024392` → exactly `Date(timeIntervalSince1970:
    1785024392)` (epoch-seconds regression guard — a ms interpretation
    would be off by ~56,000 years).
  - `reset_at` null with `reset_after_seconds: 3600` → `now + 3600` for an
    injected `now`; both null → `resetsAt == nil`, limit still emitted.
- **AC 4 (disconnected, never stale)**:
  - Transport returning 401 (captured `invalid_request_error` body) and
    403 → `notConnected`; 500 → `fetchFailed`; thrown
    `URLError(.notConnectedToInternet)` → `fetchFailed`; undecodable 200
    body and unrecognized-JSON 200 body → `fetchFailed`.
  - Store integration (one test, reusing S02's pattern): a `UsageStore`
    whose ChatGPT provider first succeeds then throws ends `.disconnected`
    with the prior limits gone and `menuBarText == "—"` — thrown errors
    can never leave stale numbers.

Manual smoke (Codex runs; user confirms at review — machine has live
credentials):

- Launch the built app → ChatGPT tab shows the real weekly percentage and
  the named model limit; cross-check against `codex` → `/status`.
- Select the ChatGPT weekly limit → menu bar shows its percentage.
- Wi-Fi off, panel Refresh → ChatGPT tab shows the network message, menu
  bar shows `—`; Wi-Fi on, Refresh → numbers return (AC 4 live).
- Optional signed-out check: `mv ~/.codex/auth.json ~/.codex/auth.json.bak`
  → Refresh → "Not signed in to Codex"; **immediately** `mv` it back and
  refresh again. Do not run `codex` while the file is moved. (Unlike S02's
  Keychain, this is a plain file and fully restorable — but skipping this
  check is fine; unit tests cover the path.)

### Risks / open questions

- **Undocumented endpoint**: `/backend-api/wham/usage` is Codex CLI's
  internal surface, not a public contract. Mitigated exactly like S02:
  tolerant decoding (only needed keys), `hasRecognizedPayload` guard, and
  the store's disconnected state — the app degrades to "disconnected",
  never to wrong numbers. Repair path: re-capture the fixture from the
  then-current codex binary/endpoint.
- **Token staleness**: the access token lives ~10 days; if the user
  doesn't run `codex` for longer, the app shows "Codex session expired —
  run codex to refresh it" until they do. Accepted v1 limitation — the
  alternative (refreshing ourselves) risks invalidating Codex CLI's
  rotating refresh token and is explicitly rejected.
- **Limits scope**: the ChatGPT subscription's readable limits are the
  Codex-surface windows + named model limits; chat-only quotas (deep
  research etc.) are not exposed by any credential-safe API. The mock's
  invented "Deep research" row disappears. If OpenAI later exposes more,
  `additional_rate_limits[]` mapping picks up new named entries
  automatically.
- **Persisted selection migration**: a user who had the mock ChatGPT
  `session`/`weekly`/`deep-research` limit selected sees `—` until they
  re-pick (real ids are `primary`/`feature:*`). One-time, self-healing via
  the panel; same accepted pattern as S02 (user approved 2026-07-18).
- **Plan-shape variance**: on this `prolite` account the secondary window
  and `code_review_rate_limit` are null; other plans populate them. The
  mapping is window-generic and duration-named, and the synthetic fixture
  keeps that path tested despite not being observable live here.
- **Workspace/team accounts**: `ChatGPT-Account-Id` selects the account;
  we send whatever Codex stored, so we always mirror the account Codex
  itself uses. Good enough by definition of the story.
- **Fixed `~/.codex` path**: a custom `$CODEX_HOME` is not honored
  (GUI apps don't inherit shell exports anyway). Accepted v1 limitation.

### Codex handoff

Branch: `feat/chatgpt-limits-provider` (cut from `main` at/after `7fc58be`).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M01-S03-chatgpt-limits-provider.md on branch feat/chatgpt-limits-provider."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox keeps
`.git` read-only, so `git switch`/`git commit` fail without it — see
`.project/memory/codex-sandbox-git.md`.)

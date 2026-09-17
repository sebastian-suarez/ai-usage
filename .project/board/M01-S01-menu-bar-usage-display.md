---
id: M01-S01
type: story
title: Menu bar usage display
status: done
priority: P1
notion: "3a2ea0aa-87b0-810b-adb9-e32ce36d096d"
github: ""
parent: "[[M01-mvp]]"
---

Turn the app into a menu bar-only app. The menu bar item always shows the
percentage used of the currently selected limit; clicking it opens a panel
listing every limit of that limit's provider as a labelled progress row. The
user picks which limit (and thereby which provider) drives the menu bar figure.

- [x] Runs as a menu bar app only — no Dock icon, no main window
- [x] Menu bar item shows the selected limit's percentage used
- [x] Clicking opens a panel with all limits of the selected limit's provider, each with name, % used, and reset time when known
- [x] The displayed limit can be changed from the panel and the choice persists across launches
- [x] Limits refresh when the panel opens and periodically in the background

## Plan

### Approach

Replace the untouched Xcode template (WindowGroup + SwiftData demo) with a
SwiftUI **`MenuBarExtra` scene in `.menuBarExtraStyle(.window)`** — the label is
a live SwiftUI view showing the selected limit's percentage, and the window
style hosts the limits panel as arbitrary SwiftUI content. The panel content is
mounted when the panel opens and unmounted when it closes, so `.onAppear` on
the panel root is the native "refresh on open" hook.

Because S02 (Claude) and S03 (ChatGPT) are implemented later, this story also
**defines the provider contract** they will conform to, and ships **two mock
providers** (ids `claude` / `chatgpt`, display names marked "(sample)") so
every acceptance criterion is exercisable with fake data today. Provider ids
match the future real providers so the persisted selection survives the swap.

Core decisions (alternatives rejected):

- **`MenuBarExtra` over `NSStatusItem` + NSPopover**: pure SwiftUI, the label
  re-renders automatically from an `@Observable` store, no AppKit plumbing
  (event monitors, popover dismissal). Deployment target is macOS 26.5, so API
  availability is a non-issue. NSStatusItem rejected: more code, no functional
  gain at this scope.
- **Hide Dock icon via `INFOPLIST_KEY_LSUIElement = YES`** build setting on the
  app target (both configs). The project uses `GENERATE_INFOPLIST_FILE = YES`;
  creating a physical Info.plist was rejected as needless churn. Removing the
  `WindowGroup` entirely guarantees no main window.
- **SwiftData is deleted, persistence is `UserDefaults`**: the only persistent
  state is "which limit is selected" — two string keys (`selectedProviderID`,
  `selectedLimitID`). The store takes an injected `UserDefaults` instance (not
  `@AppStorage`) so tests can use a throwaway suite. SwiftData rejected as
  overkill; `Item.swift`, `ContentView.swift`, and the `ModelContainer` go.
- **State lives in one `@Observable` `UsageStore`** created by the App and
  passed to label + panel. The app target builds with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything is implicitly
  main-actor; provider fetches are `async` and suspend, so no extra isolation
  annotations are needed — do not fight the default.
- **Refresh policy**: immediate `refreshAll()` at launch, then a repeating
  store-owned `Task` every **5 minutes** (constant), plus `refreshAll()` on
  panel `.onAppear`. A re-entrancy guard (`isRefreshing`) skips overlapping
  refreshes. Providers are refreshed sequentially — at n=2 providers,
  concurrency buys nothing and sequential is deterministic to test.
- **Failure semantics** (mirrors S02/S03 acceptance "never stale numbers"): a
  failed fetch replaces that provider's state with `.disconnected(message:)`,
  discarding previous limits. Menu bar shows `—` whenever the selected limit's
  value is unknown (no selection yet, provider disconnected, or first fetch
  still loading).
- **Menu bar label is bare text**: `"73%"` with monospaced digits, `"—"` when
  unknown. A provider glyph/icon next to it was rejected for now (keep it
  minimal; revisit if the user wants one).
- **No child task files**: single cohesive story-level plan — one UI +
  scaffolding chunk on one branch is the clearest execution path for Codex.

Provider contract (S02/S03 will conform to exactly this; signatures are the
deliverable, keep them):

```swift
struct UsageLimit: Identifiable, Equatable, Sendable {
    let id: String            // stable within a provider, e.g. "session", "weekly"
    let name: String          // display name, e.g. "Session"
    let usedFraction: Double  // 0.0 ... 1.0 (clamp for display)
    let resetsAt: Date?       // nil when the source doesn't provide one
}

enum UsageProviderError: Error, Equatable {
    case notConnected(String) // signed out / no credentials
    case fetchFailed(String)  // network or parse failure
}

protocol UsageProvider {
    var id: String { get }           // "claude", "chatgpt"
    var displayName: String { get }  // "Claude", "ChatGPT"
    func fetchLimits() async throws -> [UsageLimit]  // throws UsageProviderError
}

enum ProviderState: Equatable {      // owned by the store, keyed by provider id
    case loading                     // no data yet
    case connected(limits: [UsageLimit], asOf: Date)
    case disconnected(message: String)
}
```

`ProviderRegistry.defaultProviders()` returns the mock pair and is the **single
swap point** where S02/S03 later substitute real providers.

Store behavior spec:

- `UsageStore(providers:defaults:)` — registry order defines display order.
- `selection: LimitSelection?` (`providerID` + `limitID`), loaded from defaults
  at init, written on every change via `select(providerID:limitID:)`.
- After a successful `refreshAll()`, if `selection == nil`, auto-select the
  first limit of the first connected provider (first-launch default).
- `menuBarText: String` — `"NN%"` (fraction clamped to 0...1, rounded to whole
  percent) when the selected limit is present in a `.connected` state, else `"—"`.
- `startAutoRefresh(interval: Duration = .seconds(300))` — idempotent; spawns
  the repeating task (refresh, sleep, repeat). Not started in `init`, so tests
  stay deterministic; the App calls it once at startup.

Panel structure (fixed width ~320):

1. Provider `Picker` (segmented) — the *viewed* provider; defaults to the
   selected limit's provider (or the first provider when no selection). This is
   how the user reaches the other provider's limits.
2. Limit rows for the viewed provider: name, `ProgressView(value:)`, percent
   text, "resets \(resetsAt.formatted(.relative(presentation: .named)))" when
   `resetsAt != nil`, and a checkmark on the selected row. Clicking a row calls
   `select(...)` — that changes the menu bar figure (and its provider).
   Disconnected providers render their message instead of rows; loading renders
   a spinner.
3. Footer: "Updated \(asOf, relative)" text, a Refresh button
   (`refreshAll()`), and a Quit button (`NSApp.terminate(nil)`, `⌘Q`).

Mock providers: `MockUsageProvider(id:displayName:baseLimits:latency:jitter:failure:)`
with `private(set) var fetchCount` for tests. Defaults: ~300 ms latency and a
small random jitter applied to `usedFraction` each fetch so refreshes are
visible in the UI; tests pass `latency: .zero, jitter: 0`. Factories:
`.claudeSample` (Session 62% resets +2 h, Weekly 34% resets +4 d, Weekly Opus
11% resets +4 d) and `.chatGPTSample` (Session 45% resets +1 h, Weekly 72%
resets +3 d, Deep research 80% with `resetsAt: nil` — exercises the
"reset time when known" path).

### Files to touch

Project uses Xcode file-system-synchronized groups — adding/deleting `.swift`
files on disk is enough; **the only `project.pbxproj` edit is the LSUIElement
setting**.

- `AI usage.xcodeproj/project.pbxproj` — add `INFOPLIST_KEY_LSUIElement = YES;`
  to the app target's Debug (`D4F0409A…`) and Release (`D4F0409B…`)
  `buildSettings` (next to the other `INFOPLIST_KEY_*` line). Nothing else.
- `AI usage/AI_usageApp.swift` — rewrite: `MenuBarExtra` scene, store creation,
  `startAutoRefresh()`; drop SwiftData.
- `AI usage/ContentView.swift` — **delete**.
- `AI usage/Item.swift` — **delete**.
- `AI usage/Models/UsageLimit.swift` — new: `UsageLimit`, `LimitSelection`,
  `ProviderState`.
- `AI usage/Providers/UsageProvider.swift` — new: protocol + `UsageProviderError`.
- `AI usage/Providers/MockUsageProvider.swift` — new: mock + sample factories.
- `AI usage/Providers/ProviderRegistry.swift` — new: `defaultProviders()` (the
  S02/S03 swap point).
- `AI usage/UsageStore.swift` — new: the `@Observable` store per spec above.
- `AI usage/Views/MenuBarLabel.swift` — new: `Text(store.menuBarText)` with
  `.monospacedDigit()`.
- `AI usage/Views/LimitsPanel.swift` — new: panel per structure above.
- `AI usage/Views/LimitRow.swift` — new: one limit row.
- `AI usageTests/AI_usageTests.swift` — **delete** (template).
- `AI usageTests/UsageStoreTests.swift` — new.
- `AI usageTests/MockUsageProviderTests.swift` — new.
- `README.md` — add one sentence to Getting started noting the app shows
  sample data until the provider stories land. The existing architecture
  diagram already matches this design — leave it.
- Do **not** touch `AI usageUITests/` (files stay, compile, and are excluded
  from test runs), `Assets.xcassets`, or entitlements/sandbox settings.

### Steps

Environment note for every build/test command: `xcode-select` points at
CommandLineTools on this machine, so prefix all `xcodebuild` invocations with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 26.6,
verified working; no sudo needed). Scheme name is `AI usage`.

1. **LSUIElement build setting** — the two-line `project.pbxproj` edit above.
   Verify: `DEVELOPER_DIR=… xcodebuild -project "AI usage.xcodeproj" -scheme
   "AI usage" -configuration Debug build` succeeds, and the built app's
   `Contents/Info.plist` contains `LSUIElement => 1` (`plutil -p`; get the app
   path from `-showBuildSettings | grep ' BUILT_PRODUCTS_DIR'`).
2. **Strip the template** — delete `Item.swift` + `ContentView.swift`; rewrite
   `AI_usageApp.swift` as a minimal `MenuBarExtra("AI Usage") { EmptyView() }
   label: { Text("—") }` with `.menuBarExtraStyle(.window)`; no SwiftData.
   Verify: builds; `open` the built app → menu bar item shows `—`, no Dock
   icon, no window.
3. **Domain types + provider contract** — add `Models/UsageLimit.swift` and
   `Providers/UsageProvider.swift` exactly per the contract sketch. Verify: builds.
4. **Mocks + registry** — add `MockUsageProvider.swift` (incl. `.claudeSample`
   / `.chatGPTSample`, `fetchCount`) and `ProviderRegistry.swift`. Verify: builds.
5. **UsageStore** — add `UsageStore.swift` per the behavior spec (injected
   defaults, selection persistence, `refreshAll` with re-entrancy guard and
   disconnect-on-failure, auto-select-first, `menuBarText`,
   `startAutoRefresh`). Verify: builds (logic is covered by step 7 tests).
6. **UI wiring** — `MenuBarLabel`, `LimitsPanel`, `LimitRow`; App creates the
   store (`@State`), calls `startAutoRefresh()` once, panel root runs
   `.onAppear { Task { await store.refreshAll() } }`. Verify manually: run the
   app and walk all five acceptance criteria with sample data (see Test plan).
7. **Unit tests** — replace the template test file with `UsageStoreTests` +
   `MockUsageProviderTests` (list below). Gotcha: the test target does NOT set
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so annotate test suites
   `@MainActor` to use `UsageStore`; use
   `UserDefaults(suiteName: "test-…UUID…")` and `removePersistentDomain` in
   teardown; use zero-latency, zero-jitter mocks. Verify:
   `DEVELOPER_DIR=… xcodebuild -project "AI usage.xcodeproj" -scheme "AI usage"
   -destination 'platform=macOS' test -only-testing:"AI usageTests"` passes.
8. **README touch** — the one-sentence sample-data note. Verify: rendered
   markdown reads correctly; diagram untouched.

### Test plan

Automated (Swift Testing, `AI usageTests`, run with `-only-testing:"AI usageTests"`;
UI tests are deliberately excluded — XCUITest launch is unreliable for
LSUIElement apps):

- `MockUsageProviderTests`: returns the configured limits with stable ids;
  fractions within 0...1 after jitter; configured `failure` throws; `fetchCount`
  increments per fetch.
- `UsageStoreTests`:
  - `select(...)` writes both defaults keys; a **new store** constructed over
    the same defaults restores the selection → AC 4 (persists across launches).
  - `refreshAll()` populates `.connected` with `asOf`, and `menuBarText`
    formats the selected limit (`0.73 → "73%"`, clamped >1 → `"100%"`) → AC 2.
  - No selection / provider `.disconnected` / still `.loading` → `menuBarText == "—"`.
  - Failing provider (mock with `failure:`) ends `.disconnected` and prior
    limits are gone (no stale numbers), while the other provider stays connected.
  - First successful `refreshAll()` with empty defaults auto-selects the first
    limit of the first provider.
  - `startAutoRefresh(interval: .milliseconds(10))` → poll with a deadline
    until `fetchCount >= 2`, proving periodic refresh → AC 5 (periodic half).
  - Store state exposes all limits incl. one with `resetsAt == nil` → data side
    of AC 3.
- Build-artifact check (script step, not XCTest): built `Info.plist` has
  `LSUIElement = 1` → AC 1 (automatable half).

Manual smoke (Codex: run `open <built>.app` and verify; user confirms at review):

- AC 1: no Dock icon, no window; item visible in menu bar.
- AC 3: click item → panel lists the viewed provider's limits with name,
  progress, %, and reset text; the "Deep research" sample row shows no reset
  time; provider picker switches lists.
- AC 4: select a different limit → menu bar figure changes instantly; quit and
  relaunch → same limit still shown.
- AC 5: reopening the panel visibly re-fetches (mock jitter changes numbers).

### Risks / open questions

- Sample numbers jitter on every refresh by design — providers are fake until
  S02/S03; display names carry "(sample)" so this can't be mistaken for real data.
- The app sandbox currently has **no outgoing-network entitlement**; S02/S03
  must add `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (and reading local CLI
  credentials under sandbox may force revisiting sandboxing). Deliberately out
  of scope here — flagged for S02/S03 planning.
- If `.onAppear` ever proves unreliable for repeated panel opens (it should
  not — window-style content unmounts on close), fall back to observing
  `NSWindow.didBecomeKeyNotification` for the panel window.
- Deployment target macOS 26.5 pins the app to current macOS — acceptable,
  personal-machine app (host runs 26.5.2).
- Timing-based auto-refresh test can flake under load — poll with a generous
  deadline (~2 s) rather than a fixed sleep.
- **User decision, non-blocking (defaults chosen)**: menu bar shows bare
  percent text with no provider icon; background refresh every 5 minutes. Say
  the word at review if either should change.

### Codex handoff

Branch: `feat/menu-bar-usage-display`

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra \
  "Read AGENTS.md, then implement the plan in .project/board/M01-S01-menu-bar-usage-display.md on branch feat/menu-bar-usage-display."
```

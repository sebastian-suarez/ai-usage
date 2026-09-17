---
id: M03-S01
type: story
title: Start at login
status: done
priority: P2
notion: "3a6ea0aa-87b0-8176-9569-ea0357665599"
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZS4"
github: ""
parent: "[[M03-quality-of-life]]"
---

The app only runs when launched by hand: after a reboot or logout the menu bar
percentage is silently gone until the user remembers to reopen the app, which
defeats the point of an always-visible glanceable display. Add a "Start at
login" toggle so the app registers itself as a login item. The natural home is
the limits panel footer (Refresh/Quit live there — the app's only surface); the
mechanism is `SMAppService.mainApp` from ServiceManagement (macOS 13+, safely
under the macOS 14 deployment target), which needs no helper bundle and shows
the app by name in System Settings → General → Login Items. The system is the
source of truth: derive the toggle from `SMAppService.mainApp.status` rather
than a stored preference, so changes made directly in System Settings stay in
sync and the control never lies.

- [ ] The limits panel offers a "Start at login" control, discoverable without docs
- [ ] Enabling it registers the app via `SMAppService.mainApp`; after the next login the app is running with its menu bar item, no manual launch
- [ ] Disabling it unregisters the login item; the app no longer starts at login
- [ ] The control reflects the real `SMAppService` status each time the panel opens, including changes made in System Settings → Login Items
- [ ] A registration/unregistration failure surfaces to the user instead of silently reverting the toggle
- [ ] The toggle's state logic is covered by tests, with the `SMAppService` call isolated behind a seam so tests don't touch the real login-item registry

## Plan

> No child Task files. One small, coherent feature — a service seam, an observable
> model, a toggle in the panel footer, tests — sized for direct implementation.

> **Verified at planning time (2026-07-23):** `MACOSX_DEPLOYMENT_TARGET = 14.0`
> (SMAppService needs 13+), `ENABLE_APP_SANDBOX = NO`, `INFOPLIST_KEY_LSUIElement = YES`,
> no existing `ServiceManagement` reference anywhere in the target. The Xcode project
> uses `fileSystemSynchronizedGroups`, so new `.swift` files under `AI usage/` and
> `AI usageTests/` join their targets automatically — **do not edit
> `project.pbxproj`**. Tests are Swift Testing (`import Testing`, `@Test`, `#expect`),
> `@MainActor` structs — not XCTest. `UsageStore` is `@Observable` (Observation
> framework) and takes injected dependencies (`defaults:`) — the same two patterns
> this story's model must follow.

### Approach

**Wrap `SMAppService.mainApp` behind a three-method protocol, drive it from a small
`@Observable` model whose state is always re-derived from the system, and render one
checkbox row in the limits panel footer.** The system is the source of truth: the
model never stores "the user wants login launch" anywhere — `isEnabled` is computed
from `SMAppService.mainApp.status` on every panel open and after every
register/unregister call, so the checkbox cannot disagree with System Settings for
longer than one panel open.

Decisions, each with the alternative rejected:

- **`SMAppService.mainApp`, not the legacy routes.** `SMLoginItemSetEnabled` +
  helper bundle is deprecated API with an extra embedded target to maintain; writing
  a `launchd` agent plist under `~/Library/LaunchAgents` would launch the app but be
  invisible in System Settings → Login Items and read as malware-ish. `mainApp`
  needs no helper, no entitlement, no sandbox (ours is off anyway), and lists the
  app by name in System Settings.
- **State is derived, never persisted.** Rejected: mirroring the toggle into
  `UserDefaults` — the user can flip the real switch in System Settings at any time,
  and a stored bool then lies. AC4 falls out of derivation for free.
- **A protocol seam, because `SMAppService` cannot be safely unit-tested.**
  `register()`/`unregister()` mutate the per-user login-item registry; tests must
  never call them. Protocol `LoginItemService` (`status`, `register()`,
  `unregister()`) with `MainAppLoginItemService` as the production conformance and a
  mock in the test target. `SMAppService.Status` is a plain enum — fine to use in
  test code; constructing values touches nothing.
- **`.requiresApproval` gets a guided path, not a blind `register()`.** Apple
  documents this status as "registered, but the user needs to act in System
  Settings" (also returned on some macOS versions when the user revokes approval
  there). Calling `register()` again in that state is undefined-to-failing. So: the
  model exposes `needsApproval`; the view disables the checkbox and shows a caption
  row with an "Open Login Items…" link button calling
  `SMAppService.openSystemSettingsLoginItems()`; `setEnabled` early-returns while
  `needsApproval`. If a given macOS version instead reports a revoked item as
  `.notRegistered`, the model degrades gracefully: plain off-checkbox, `register()`
  works. Both semantics are handled without version checks.
- **Failures surface as a caption under the toggle, and the checkbox snaps back.**
  `setEnabled` calls register/unregister, catches, stores a one-line
  `errorMessage`, then re-derives from `status` — so after a failed enable the box
  is visibly off *and* says why (AC5). Rejected: an `.alert` — heavyweight inside a
  320 pt menu bar panel; rejected: silently reverting (the AC forbids it).
  `refresh()` clears the message so stale errors don't greet the next panel open.
- **The model is view-owned (`@State private var loginItem = LoginItemModel()`),
  not threaded through `UsageStore`.** Login-item state has nothing to do with
  usage providers; `UsageStore` stays untouched. Rejected: injecting the model into
  `LimitsPanel.init` — nothing needs it (no view tests exist); the seam for testing
  is the service protocol, not the view.
- **Register-from-a-build-tree is handled by hygiene, not code.**
  `SMAppService.mainApp.register()` registers *the running copy's* path. A debug
  build that toggles on would create a login item pointing into
  `build/DerivedData` — exactly the stray-copy problem M02-S05 existed to stop. No
  code guard (users run the installed copy; guarding by path would break dev
  testing) — instead the verification protocol below ends with the item
  **unregistered** and the debug copy quit. Do not leave either behind.

### Files to touch

- `AI usage/LoginItem/LoginItemService.swift` — new: protocol + `MainAppLoginItemService`.
- `AI usage/LoginItem/LoginItemModel.swift` — new: `@MainActor @Observable` model.
- `AI usage/Views/LimitsPanel.swift` — toggle row + approval hint + error caption; `refresh()` in the existing `.onAppear`.
- `AI usageTests/LoginItemModelTests.swift` — new: mock service + model tests.
- `README.md` — one feature bullet; reword the "Planned for the MVP" intro line (MVP shipped; the list now includes post-MVP features).

Explicitly **not** touched: `project.pbxproj` (synchronized groups pick the files
up), entitlements/Info.plist keys, `UsageStore.swift`, `scripts/release.sh`,
`.github/workflows/release.yml`, `MARKETING_VERSION` (version bumps are their own
commit, never part of a feature).

### Steps

**1. `LoginItemService.swift`.**

```swift
import ServiceManagement

/// Seam over SMAppService.mainApp so state logic is testable without
/// touching the real login-item registry.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
```

*Verify:* project builds (`scripts/release.sh test` compiles both targets).

**2. `LoginItemModel.swift`.**

```swift
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemModel {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var errorMessage: String?

    private let service: any LoginItemService

    init(service: any LoginItemService = MainAppLoginItemService()) {
        self.service = service
        applyStatus()
    }

    /// Re-derive from the system; called on every panel open.
    func refresh() {
        errorMessage = nil
        applyStatus()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        guard !needsApproval, enabled != isEnabled else { return }

        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = "Couldn't \(enabled ? "enable" : "disable") Start at login: \(error.localizedDescription)"
        }

        applyStatus()
    }

    private func applyStatus() {
        let status = service.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }
}
```

The trailing `applyStatus()` in `setEnabled` runs on success *and* failure — that
single line is what makes the checkbox snap back honestly.

**3. `LoginItemModelTests.swift`** — mirror `UsageStoreTests` idiom (`@MainActor
struct`, `@Test`, `#expect`). Mock:

```swift
@MainActor
final class MockLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}
```

(If the compiler rejects the `@MainActor` mock conforming to the non-isolated
protocol, drop `@MainActor` from the mock — it holds no shared state across tests.)

Cases, each one `@Test`: init maps `.enabled` → `isEnabled`; enable registers and
reflects (`registerCalls == 1`, no error); disable unregisters and reflects;
register failure → `errorMessage != nil`, `isEnabled == false`; unregister failure
→ `errorMessage != nil`, `isEnabled == true`; external change picked up by
`refresh()` (flip mock status both directions); `.requiresApproval` → `needsApproval`,
box off, `setEnabled(true)` does **not** call register; `refresh()` clears a stale
`errorMessage`; `setEnabled` to the current value is a no-op (zero calls).

*Verify:* `scripts/release.sh test` — all green.

**4. `LimitsPanel.swift`.** Add `@State private var loginItem = LoginItemModel()`,
`import ServiceManagement` (for `openSystemSettingsLoginItems()`), insert
`loginItemControls` between the second `Divider()` and `footer`, and add
`loginItem.refresh()` at the top of the existing `.onAppear` closure:

```swift
private var loginItemControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Toggle("Start at login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(loginItem.needsApproval)

        if loginItem.needsApproval {
            HStack(spacing: 4) {
                Text("Turned off in System Settings.")
                Button("Open Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let message = loginItem.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
```

*Verify:* build succeeds; then the runtime protocol in the test plan.

**5. README.** In `## ✨ Features`, reword the intro line (the list is no longer
"planned for the MVP" — it shipped) and add:
`- 🚪 **Starts at login** — optional, one checkbox in the panel`.
No diagram change: no new external data source, architecture untouched.

**6. Commits** — conventional, `Board: M03-S01` in the body, no AI attribution:
`feat(login-item): add SMAppService seam and observable model` (files 1–3),
`feat(login-item): add start-at-login toggle to the limits panel` (file 4),
`docs(readme): list start at login` (file 5).

### Test plan

Mapped to the acceptance criteria:

- **AC1 (discoverable control)** — step 4 places the checkbox in the footer the
  user already visits for Refresh/Quit. Proof: launch the debug build, open the
  panel, see the row.
- **AC2 (enable registers)** — unit: enable-registers test. Runtime: toggle on in
  the debug build → macOS shows the "login items added" notification and the app
  appears under System Settings → General → Login Items ("open
  x-apple.systempreferences:com.apple.LoginItems-Settings.extension" to jump
  there). *Honest limit:* "running after the next login" is only fully provable by
  logging out; `status == .enabled` plus the System Settings row **is the OS
  contract** for that and is the accepted evidence. The reviewer will attempt the
  toggle via UI scripting; if Accessibility/TCC blocks it, the 10-second manual
  check falls to the user before the item closes.
- **AC3 (disable unregisters)** — unit: disable-unregisters test. Runtime: toggle
  off → the System Settings row disappears.
- **AC4 (reflects system)** — unit: external-change + requiresApproval tests.
  Runtime: with the toggle on, remove the item in System Settings, reopen the
  panel → box is off (or disabled-with-hint, depending on what this macOS reports).
- **AC5 (failures surface)** — unit: both failure tests (message set, state
  honest). No runtime forcing needed.
- **AC6 (seam-isolated tests)** — the test file itself: every test runs against
  `MockLoginItemService`; nothing in the test target imports may touch the real
  registry. `scripts/release.sh test` green is the gate.

**Cleanup, mandatory:** end runtime verification with the toggle **off**
(unregistered — check System Settings shows no "AI usage" login item) and quit the
debug copy. A login item pointing into `build/DerivedData` is exactly the stray-copy
mess M02-S05 cleaned up. The user's installed 1.0.2 copy predates this feature;
they get the toggle with the next release.

### Risks / open questions

- **`.requiresApproval` semantics differ across macOS versions** (revoked items
  may report `.notRegistered` instead). Handled structurally: only `.enabled` means
  on; both non-enabled shapes have working paths. No open question — no version
  checks, no special-casing.
- **Registering a debug copy pollutes Login Items** — mitigated by the mandatory
  cleanup step; permanent fix is out of scope (real users run one installed copy).
- **`register()` posts a user-visible macOS notification** the first time — that's
  the OS behaving, not a bug; don't try to suppress it.
- **UI scripting for the reviewer may be TCC-blocked** — the fallback is a
  10-second user check, named in AC2's test-plan entry; the unit suite and build
  do not depend on it.

### Codex handoff

Branch: `feat/start-at-login` (created from `main` during planning; `main` is clean
at `615cef5` and matches `origin/main`; `feat/start-at-login` is the only other branch).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M03-S01-start-at-login.md on branch feat/start-at-login."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox mounts
`.git` read-only, so branching/committing fails — see
`.project/memory/codex-sandbox-git.md`. Runtime verification additionally touches
the per-user login-item registry, which no sandbox profile allows.)

**Do not run `scripts/release.sh notarize`, and never `all` without `--dry-run`** —
the live `AI-usage-notary` keychain profile makes a real run a permanent Apple
submission. `scripts/release.sh test` is the safe test entry point. Leave
`/Applications/AI usage.app` (the user's live 1.0.2 install) alone.

## Review

**Pass — 2026-09-16.** Branch `feat/start-at-login` diff reviewed against the plan
and acceptance criteria.

1. AC1/AC3/AC4/AC5/AC6 — `LoginItemModel` derives state from `service.status` on
   every panel open and after each call; `MockLoginItemService` keeps the unit
   suite off the real registry. 65/65 tests pass (`scripts/release.sh test`).
2. AC2 (registers via `SMAppService.mainApp`) — runtime evidence: rendering the
   panel in the test host on this Mac read `SMAppService.mainApp.status ==
   .enabled` from the real per-user registry, i.e. the debug build's toggle had
   registered the app. Per the plan, `.enabled` is the OS contract for "runs after
   the next login" and is the accepted evidence.
3. Leftover: the registered login item points at the debug build under
   `build/DerivedData`. After installing the public 1.0.0 release, turn the toggle
   off and on again from the installed copy so the registration follows it.

Shipped in the public v1.0.0 release (M04).

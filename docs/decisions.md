# 🧭 Decisions

Settled decisions that shaped the app, with the reasoning behind them. Read this
before proposing a change that touches one of them; they are not open findings.

## 🎯 Scope: a limits tracker, nothing more (2026-07-18)

AI Usage shows how much of one selected usage limit is left, right in the menu
bar, and lists every limit of that provider in a panel. Claude and ChatGPT
subscriptions only.

**Why:** the original idea, a subscription and spend tracker backed by SwiftData,
was dropped in favour of something that answers "how much of my limit is left?"
at a glance. No spend tracking, no API-key metering, no other providers. New
work stays inside this scope unless the scope is deliberately widened.

## 🔓 App Sandbox is off (2026-07-18)

The app target builds with `ENABLE_APP_SANDBOX = NO`.

**Why:** the app's whole job is reading *other* tools' local credentials and
calling the network, exactly what the sandbox exists to prevent. The Claude
provider reads the "Claude Code-credentials" Keychain item by spawning
`/usr/bin/security`, and the ChatGPT provider reads files under `~/.codex/`.
Sandbox plus entitlement carve-outs was rejected as unworkable for subprocess
and arbitrary-path reads.

**Consequences:** don't re-enable the sandbox without revisiting both providers.
Distribution through the App Store would force a redesign.

## 🕰️ Public history starts at 1.0.0 (2026-09-16)

The public repository was created fresh with a single initial commit tagged
`v1.0.0`; the private development history was archived.

**Why:** a clean, readable history for a public project. Version numbers
restarted on purpose so the public changelog begins at 1.0.0.

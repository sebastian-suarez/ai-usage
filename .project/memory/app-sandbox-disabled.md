# App Sandbox is off — deliberate, user-approved

Approved 2026-07-18 (M01-S02 planning): the app target builds with
`ENABLE_APP_SANDBOX = NO`.

**Why:** the app's whole job is reading *other* tools' local credentials and
calling the network — things the sandbox exists to stop. The Claude provider
reads the "Claude Code-credentials" Keychain item by spawning
`/usr/bin/security`, and M01-S03 (ChatGPT) will need to read `~/.codex/`
files. Sandbox + entitlement carve-outs was rejected as unworkable for
subprocess + arbitrary-path reads.

**Consequences:** don't re-enable the sandbox in future stories without
revisiting both providers; reviewers should treat the setting as settled, not
a finding. Distribution outside the user's own machine (e.g. App Store) would
force a redesign.

---
id: M03-S02
type: story
title: Cache Claude credentials to stop keychain prompt spam
status: backlog
priority: P1
notion: "3adea0aa-87b0-8178-99c7-d91206922386"
github: ""
parent: "[[M03-quality-of-life]]"
---

Every refresh (auto-refresh every 5 minutes, plus manual Refresh) spawns
`/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` to read
Claude Code's OAuth token, and macOS raises a keychain password prompt for each
spawn unless the user has granted Always Allow — and even then, Claude Code
rewriting the item on token refresh can reset that permission, so the prompts
keep coming back. The provider already knows the token's `expiresAt`, so there is
no reason to hit the keychain while a previously read token is still valid: cache
the credentials in memory and re-read the keychain only when the cache is empty,
the token is expired or near expiry, or the usage API rejects it. This collapses
the prompt frequency from every-5-minutes to roughly once per token lifetime,
without touching how credentials are found (keychain first, file fallback
unchanged).

**On hold (2026-09-16):** the prompt storm that motivated this story was traced to a
Claude Code switch that rewrote the keychain item, not to the app's polling. Kept
in the backlog as an optimization, no longer a usability blocker.

- [ ] Steady-state auto-refresh performs no keychain reads while a cached access token is still valid (with a sensible expiry margin)
- [ ] The keychain is re-read only when there are no cached credentials, the cached token is expired/near expiry, or the usage API rejects the token — a rejection invalidates the cache so the next load re-reads
- [ ] Manual Refresh follows the same policy — it never forces a keychain read while the cached token is valid
- [ ] The existing lookup order and error messages are unchanged when a real read does happen (keychain first, `~/.claude/.credentials.json` fallback, same not-connected messages)
- [ ] Caching behavior is covered by tests through the existing `ClaudeCredentialsSource` seam; tests never touch the real keychain

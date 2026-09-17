# Memory index — AI Usage

<!-- One line per memory file: - [Title](file.md) — hook -->
- [Product scope](product-scope.md) — menu bar limits app for Claude + ChatGPT subscriptions only; spend-tracker idea dropped 2026-07-18
- [App Sandbox off](app-sandbox-disabled.md) — ENABLE_APP_SANDBOX = NO, user-approved 2026-07-18; needed for Keychain/`security` + ~/.codex/ reads, don't re-enable without revisiting providers
- [Codex sandbox vs .git](codex-sandbox-git.md) — `codex exec` handoffs need `-s danger-full-access`; workspace-write mounts `.git` read-only (no opt-out in codex-cli 0.144.6), so branching/committing fails without it
- [Public repo reset](public-repo-reset.md) — 2026-09-16 fresh public history at v1.0.0; old repo archived as ai-usage-archive + local bundle; secrets re-entered; Homebrew tap
- [GitHub Project mirror](github-project-mirror.md) — Notion retired 2026-09-17; one issue per item + sub-issues + repo Milestones; Status has workflow states; `.project/bin/board` does all writes; views are manual; gh gotchas

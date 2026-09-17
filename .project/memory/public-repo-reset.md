# Public repo reset (2026-09-16)

The GitHub repository was recreated from scratch as a public repo: history starts
at a single initial commit tagged `v1.0.0`. The public 1.0.0 is functionally the
old private 1.0.2 plus Start at login (M03-S01); version numbers restarted on
purpose so the public changelog is clean.

- Old private repo was renamed `ai-usage-archive` and deleted by the user on
  2026-09-17. The only copy of its history is the bundle in
  `~/Projects/ai-usage-archive/` (plus the 1.0.0–1.0.2 DMGs).
- `github:` fields of pre-reset board items were blanked: their PR links pointed at
  the archived repo.
- Release secrets were re-entered by the user on 2026-09-17 (the classifier blocks
  agents from exporting the `.p12` or uploading key material). Commits are unsigned:
  `commit.gpgsign` is on but no pinentry is reachable from agent shells; the user
  chose not to sign.
- Homebrew tap: `sebastian-suarez/homebrew-tap`, cask `ai-usage`, updated by hand
  per release (sha256 of the release DMG).
- `~/.claude/bin/board` (the board status/regen helper CLAUDE.md refers to) is
  missing on this machine; `BOARD.md` was regenerated with a scratch script.
- GitHub Project "AI Usage" (users/sebastian-suarez/projects/1) created and linked
  to the repo on 2026-09-17 after the user added the `project` scope to `gh`;
  node ID and URL are in `.project/config.json`.

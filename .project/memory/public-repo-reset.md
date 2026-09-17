# Public repo reset (2026-09-16)

The GitHub repository was recreated from scratch as a public repo: history starts
at a single initial commit tagged `v1.0.0`. The public 1.0.0 is functionally the
old private 1.0.2 plus Start at login (M03-S01); version numbers restarted on
purpose so the public changelog is clean.

- Old private repo renamed to `sebastian-suarez/ai-usage-archive` (to be deleted by
  the user; the `gh` token lacks the `delete_repo` scope). Full history bundle and
  the 1.0.0–1.0.2 DMGs are in `~/Projects/ai-usage-archive/`.
- `github:` fields of pre-reset board items were blanked: their PR links pointed at
  the archived repo.
- Release secrets had to be re-entered on the new repo; the Developer ID `.p12`
  export needs the user (interactive keychain access).
- Homebrew tap: `sebastian-suarez/homebrew-tap`, cask `ai-usage`, updated by hand
  per release (sha256 of the release DMG).
- `~/.claude/bin/board` (the board status/regen helper CLAUDE.md refers to) is
  missing on this machine; `BOARD.md` was regenerated with a scratch script.

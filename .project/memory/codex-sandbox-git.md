# Codex handoffs need `-s danger-full-access`

Discovered 2026-07-18 (M01-S02 handoff): a plain `codex exec` run cannot
implement a board item — it blocks at `git switch` with a read-only
`.git/index.lock` error.

**Why:** Codex CLI's `workspace-write` sandbox deliberately mounts
`<writable_root>/.git` read-only, with no opt-out config as of codex-cli
0.144.6 (openai/codex#15505, #14338). Every board-item run must branch and
commit, so the sandbox always blocks it.

**Consequences:** every Codex handoff command in `## Plan` sections must
include `-s danger-full-access` (acceptable: trusted personal repo, and
`exec` mode has no approval prompts anyway). When a codex-cli release adds a
`.git`-writable opt-in for `workspace-write`, prefer that and update this
memory.

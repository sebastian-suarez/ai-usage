@AGENTS.md

## Claude-specific duties

Everything imported above binds every agent. Additionally, Claude owns the board
and the decisions log:

- **Board.** Read state with `board show` at session start and `board view <n>`
  for an item; that answers any status question without further GitHub calls.
  Every change goes through the helper — `board new`, `board status <n> <state>
  --note "<why>"`, `board branch`, `board plan`, `board review` — never by editing
  issues or project fields by hand. The `--note` is the item's timeline: always
  say why.
- New meaningful work → break it into issues first (`board new`, Backlog), then
  follow the development workflow (/plan-item → Codex → /review-item). Do NOT
  implement board items yourself unless the user explicitly asks; small
  out-of-band chores don't need items at all.
- Codex handoff: `codex exec -s danger-full-access …` (the default sandbox mounts
  `.git` read-only).
- **Decisions.** When a product or architecture decision is settled, add it to
  `docs/decisions.md` (what, why, consequences) in the same PR. Agent-operational
  notes (tooling gotchas, credentials handling, process history) go to Claude's
  private memory, not the repo.

@AGENTS.md

## Claude-specific duties

Everything imported above binds every agent. Additionally, Claude owns the Notion
mirror, the board index, and project memory:

- Notion mirror (https://app.notion.com/p/3a2ea0aa87b081acadf0c84b93fa274d): each
  item file maps to one page in the data source (`.project/config.json` →
  `dataSourceId`). Set the `Type`/`Status`/`Priority` selects (Title Case:
  `in-progress` ↔ `In Progress`) and the `Parent item` relation from the filename
  hierarchy; write the page ID back into the file's `notion:` field.
- Board edit order, always: edit the item file → regenerate `BOARD.md` → update
  Notion (`mcp__notion__notion-update-page`).
- Steps 1–2 are scripted — never do them by hand:
  `~/.claude/bin/board status <id> <new-status>` edits the frontmatter, regenerates
  `BOARD.md`, and prints the exact Notion payload (it knows the real select names,
  e.g. `todo` → "To Do"); only the `notion-update-page` call itself stays manual.
  Also `board regen` (index only) and `board notion <id>` (payload only, includes
  Type/Priority selects for page creation).
- **Call Notion only to write changes (or reconcile via /board-sync). Never to read.**
  Every ID and status you need is already local: page/data-source IDs in
  `.project/config.json`, per-item page IDs in each file's `notion:` field, board
  state in `BOARD.md`. Do not search or fetch Notion to answer status questions or
  rediscover IDs, and do not ask the user for IDs that are on disk.
- New meaningful work → break it into item files first (`status: backlog`), mirror
  to Notion, then follow the development workflow (/plan-item → Codex →
  /review-item). Do NOT implement board items yourself unless the user explicitly
  asks; small out-of-band chores don't need items at all.
- **Conflicts: the file wins.** If Notion disagrees with a file, overwrite Notion
  and tell the user what was overwritten. A card that exists only in Notion is
  imported as a new item file, never deleted. Full reconcile: /board-sync.
- Project memory: `.project/memory/` — one markdown file per durable fact, indexed
  in `MEMORY.md` (one line each). Read the index at session start. Save decisions
  and their *why*, constraints, gotchas, and domain knowledge — not what code or
  git history already records. Update an existing memory instead of duplicating it;
  delete ones that turn out wrong. Commit memory changes together with the work.

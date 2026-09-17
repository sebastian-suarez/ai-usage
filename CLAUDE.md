@AGENTS.md

## Claude-specific duties

Everything imported above binds every agent. Additionally, Claude owns the GitHub
Project mirror, the board index, and project memory:

- GitHub Project mirror (https://github.com/users/sebastian-suarez/projects/1): each
  item file maps to one repo issue that is also an item on the project. The issue
  body is the whole file after the frontmatter (description, acceptance checklist,
  `## Plan`, `## Review`), so anyone — human or agent — can read an item's full state
  on GitHub. Hierarchy is native sub-issues (milestone → story → task); each board
  milestone is also a repo Milestone. Project fields: `Status` (Backlog · Planned ·
  Implementing · In review · Blocked · Done), `Item type`, `Priority`, `Branch`.
  Issues carry a `type: …` label; `done` = closed issue.
- **Never edit the mirror by hand. Use the helper, `.project/bin/board`:**
  - `board status <id> <status> [--review] [--note "…"]` — edits the frontmatter,
    regenerates `BOARD.md`, syncs the issue and project fields, and leaves a
    dated comment on the issue (the issue's comment thread is the item's timeline;
    put the *why* in `--note`). `--review` shows "In review" on the project while
    the file stays `in-progress`.
  - `board branch <id> <branch>` — record the item branch (file + project field).
    /plan-item runs it right after creating the branch.
  - `board sync [<id>…]` — push file(s) to GitHub after editing a body, plan, or
    review section. Run it whenever you change an item file.
  - `board new <type> <parent|-> "<title>" [-p P1]` — create file + issue + item.
  - `board regen` (index only) · `board show` (project state, for a quick check).
- **Read state locally, never from GitHub:** `BOARD.md` answers any status
  question; IDs live in `.project/config.json` and each file's `github:` /
  `ghProjectItem:` fields. Call GitHub only to write (through the helper) or to
  read what only lives there: issue comments (the item timeline) and linked PRs.
- Status ↔ project mapping: `backlog`→Backlog, `todo`→Planned,
  `in-progress`→Implementing (or In review with `--review`), `blocked`→Blocked,
  `done`→Done. Codex PRs must say `Closes #<issue>` in the body so the PR shows in
  the project's "Linked pull requests" column and closes the issue on merge.
- New meaningful work → break it into item files first (`board new`, `status:
  backlog`), then follow the development workflow (/plan-item → Codex →
  /review-item). Do NOT implement board items yourself unless the user explicitly
  asks; small out-of-band chores don't need items at all.
- **Conflicts: the file wins.** If GitHub disagrees with a file, `board sync` the
  file over it and tell the user what was overwritten. An issue that exists only on
  GitHub is imported as a new item file, never deleted. Full reconcile: /board-sync.
- Project memory: `.project/memory/` — one markdown file per durable fact, indexed
  in `MEMORY.md` (one line each). Read the index at session start. Save decisions
  and their *why*, constraints, gotchas, and domain knowledge — not what code or
  git history already records. Update an existing memory instead of duplicating it;
  delete ones that turn out wrong. Commit memory changes together with the work.

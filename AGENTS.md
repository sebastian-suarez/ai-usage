# Project conventions

Read this fully before any work. It is the canonical conventions file for every
agent working in this repo — Codex reads it natively; Claude Code imports it via
CLAUDE.md.

## Project board — files are the source of truth

Milestones, Stories and Tasks live as markdown files in `.project/board/`. Those
files are the source of truth; the Notion board is a human-facing mirror maintained
by Claude. Config and IDs: `.project/config.json`.

Item files sit flat in `.project/board/`, hierarchy encoded in the filename —
`M01-mvp.md`, `M01-S01-user-auth.md`, `M01-S01-T01-login-form.md` (parent = filename
minus its last ID segment). Each file:

    ---
    id: M01-S01-T01
    type: task           # milestone | story | task
    title: Login form
    status: backlog      # backlog | todo | in-progress | blocked | done
    priority: P2         # P0 | P1 | P2
    notion: ""           # Notion page ID, managed by Claude
    ghProjectItem: ""    # GitHub Project item ID (PVTI_…), managed by Claude
    github: ""           # related issue/PR URL, optional
    ---

    One-paragraph description. Stories/Tasks: acceptance criteria as a `- [ ]` checklist.

`BOARD.md` is a regenerated index — one checkbox line per item, indented to show
hierarchy; checked = `done`. Milestone and Story lines carry a `(done/total)`
progress count of their direct children:

    # Board — <Project>

    - [ ] M01 [in-progress] MVP (1/2)
      - [x] M01-S01 [done] User auth (2/2)
        - [x] M01-S01-T01 [done] Login form
        - [x] M01-S01-T02 [done] Session refresh
      - [ ] M01-S02 [todo] Data layer (0/2)

Read `BOARD.md` first to learn board state — it answers any status question without
opening item files or calling Notion. Regenerate it after every board change.
Never delete item files — set `done` or move back to `backlog`.

## Development workflow (per board item)

1. **Plan — Claude (Fable 5, max effort)**: writes `## Plan` into the item file,
   creates the item branch (`<type>/<slug>`), sets `status: todo`.
2. **Implement — Codex (gpt-5.6-sol, max/ultra reasoning)**: executes the plan on the
   item branch. Rules for the implementer below.
3. **Review — Claude (Fable 5, max effort)**: judges the branch diff against the
   plan and acceptance criteria; on pass `status: done`; on fail, findings land in
   `## Review` for another Codex round.

Status semantics: `backlog` = unplanned · `todo` = planned, awaiting implementation ·
`in-progress` = implementing or in review · `blocked` = needs the user · `done` =
reviewed and closed.

## Rules for the implementer (Codex)

1. Read the item file in `.project/board/` and implement its `## Plan`, honoring the
   acceptance criteria checklist. If a `## Review` section exists, address every
   numbered finding in it.
2. Set the item's `status:` frontmatter to `in-progress` when you start.
3. Work only on the item's branch. Commit in small conventional commits, referencing
   the item in the body (`Board: <id>`).
4. `.project/memory/` is useful context (past decisions, gotchas) — read it freely,
   but never write to it. Do not touch Notion, `BOARD.md`, or other items' files —
   the review phase reconciles those.

## Git conventions

- Every commit message follows Conventional Commits: `<type>(<scope>): <description>`,
  with an optional body and `BREAKING CHANGE:` footer when applicable.
  Allowed types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`, `revert`.
  The description is imperative, lowercase, no trailing period (e.g. `feat(auth): add session refresh`).
- Branch names follow the same types: `<type>/<short-kebab-description>`
  (e.g. `feat/user-auth`, `fix/login-crash`). Never commit new work directly to `main`;
  create a branch per Story (or per Task if large).
- One logical change per commit. A commit that closes a board item should mention it
  in the body by ID (e.g. `Board: M01-S01-T01`).
- No AI attribution anywhere in git history: never add `Co-Authored-By` trailers,
  "Generated with ..." lines, or any AI/agent mention in commit messages or PR
  descriptions. The author is the user's git identity only.

## Documentation style

- The README is written for humans first: plain language, short paragraphs, *why*
  before *how* — someone new should get the project within the first screen.
- Use emojis on section headers and key bullets for scannability
  (✨ Features, 🚀 Getting started, 🏗️ Architecture) — one per header, tasteful.
- Prefer Mermaid diagrams over prose for structure: `flowchart` for architecture and
  data flow, `sequenceDiagram` for key interactions, `erDiagram`/`classDiagram` for
  data models. Schemas are shown as diagrams or annotated examples, never listed in prose.
- When a change alters architecture, data flow, or a schema, update the affected
  README diagrams in the same PR.

# Project conventions

Read this fully before any work. It is the canonical conventions file for every
agent working in this repo — Codex reads it natively; Claude Code imports it via
CLAUDE.md.

## Project board — GitHub is the source of truth

All planning lives on the GitHub Project "AI Usage"
(https://github.com/users/sebastian-suarez/projects/1) and this repo's issues.
There is no local copy of the board.

- **Items are issues.** Title `<id> · <title>`; the id encodes the hierarchy —
  `M01` milestone, `M01-S01` story, `M01-S01-T01` task. Hierarchy is native
  sub-issues (milestone → story → task); every milestone is also a repo Milestone.
  Issues carry a `type: milestone | story | task` label.
- **Issue body** = one-paragraph description, then `**Acceptance criteria**` as a
  `- [ ]` checklist (stories and tasks), then `## Plan` once planned. Review
  findings are comments titled `## Review round N`; status changes are comments
  too, so the comment thread is the item's timeline.
- **Project fields:** `Status` (Backlog · Planned · Implementing · In review ·
  Blocked · Done), `Item type`, `Priority` (P0 · P1 · P2), `Branch`
  (`<type>/<slug>`). Done = closed issue.
- **Helper:** `board`, maintainer tooling installed at `~/.claude/bin/board` and
  run from inside the repo, does every write so fields, issue state, milestones
  and comments stay consistent. `board show` lists the board, `board view <n>`
  prints an item with its fields and latest comments; `new`, `status`, `branch`,
  `plan` and `review` change it. Prefer it over raw `gh` calls.
- Never delete issues — set Done, or move back to Backlog.

## Development workflow (per issue)

1. **Plan — Claude (Fable 5, max effort)**: writes the `## Plan` section
   (`board plan <n> plan.md`), creates the item branch (`<type>/<slug>`,
   `board branch`), then `board status <n> planned`.
2. **Implement — Codex (gpt-5.6-sol, max/ultra reasoning)**: executes the plan on
   the item branch and opens a PR whose body says `Closes #<n>`.
3. **Review — Claude (Fable 5, max effort)**: `board status <n> in-review`, judges
   the PR diff against the plan and acceptance criteria. Pass → merge; the issue
   closes and the card moves to Done. Fail → `board review <n> findings.md`, back
   to `implementing` for another Codex round.

Status semantics: Backlog = unplanned · Planned = plan written, awaiting
implementation · Implementing = Codex working · In review = Claude reviewing ·
Blocked = needs the user · Done = reviewed, merged and closed.

## Rules for the implementer (Codex)

1. Read the issue first: `board view <n>` (or `gh issue view <n> --comments`).
   Implement its `## Plan`, honouring the acceptance checklist. If the latest
   comment is a `## Review round N`, address every numbered finding in it.
2. Run `board status <n> implementing` when you start.
3. Work only on the item's branch (the `Branch` field). Commit in small
   conventional commits with `Refs #<n>` in the body; the PR body must contain
   `Closes #<n>` so the PR is linked to the card and closes the issue on merge.
4. `docs/decisions.md` records settled decisions — read it before touching
   architecture, and don't relitigate them. Do not edit other issues, project
   fields other than Status, or `docs/decisions.md`; the review phase does that.

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

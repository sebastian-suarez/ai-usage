# GitHub Project mirror (2026-09-17)

Notion was retired as the board mirror on 2026-09-17; this repo is the test bed for
running the board fully on GitHub. Files stay the source of truth
(`.project/board/`), the mirror is GitHub Project "AI Usage"
(users/sebastian-suarez/projects/1; IDs in `.project/config.json`) fed by
`.project/bin/board`. The old Notion page was left untouched, not deleted.

Structure and the reasoning behind it:

- **One real issue per item** (not drafts): drafts can't have sub-issues, linked
  PRs or comments, and those three are what make the mirror useful for tracking.
  Issue body = file body plus a header line (id · type · priority · parent · branch
  · source path), so the issue is readable without the repo.
- **Hierarchy = native sub-issues** (milestone → story → task). The project's
  built-in "Parent issue" and "Sub-issues progress" columns come for free. Each
  board milestone is additionally a repo Milestone (progress bar in Issues UI),
  closed when the milestone item is done.
- **Fields:** `Status` has workflow states rather than the file's five —
  Backlog / Planned / Implementing / In review / Blocked / Done — because
  `in-progress` hides whether Codex or the review is active. `Item type`
  (GitHub reserves the name "Type"), `Priority`, `Branch` (text). Labels
  `type: milestone|story|task` make type visible in the issues list too.
- **Timeline = issue comments:** `board status` posts `old → new` plus `--note`
  on every change, so the *why* of a transition is on the card.
- **PR linkage:** Codex PRs say `Closes #N`; the native "Linked pull requests"
  column then shows the PR and merge closes the issue (built-in project workflow
  moves closed items to Done).
- Gotchas: renaming `Status` options via `updateProjectV2Field` wipes existing
  values (resync after); `gh issue edit --milestone` can't match titles
  containing "·" (helper uses REST by number); `gh project item-edit` errors with
  "no changes to make" when writing an unchanged empty text field (helper ignores
  it). Project **views** have no API — they are created by hand in the UI.

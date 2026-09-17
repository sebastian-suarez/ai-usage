# GitHub Project mirror (2026-09-17)

The board is also mirrored to GitHub Project "AI Usage"
(users/sebastian-suarez/projects/1; node ID and URL in `.project/config.json`),
alongside Notion. Files remain the source of truth.

- Every item is a **draft issue** (not a repo issue) so the public repo stays free
  of planning noise; drafts can be converted to issues later if wanted. Title is
  `<id> · <title>`, body is the item description.
- Fields: `Status` (Backlog/Todo/In Progress/Blocked/Done, mapped from the
  frontmatter like Notion), `Item type` (Milestone/Story/Task — GitHub reserves the
  name "Type"), `Priority` (P0–P2), `ID` (text), `Parent` (text, `<id> · <title>`;
  drafts can't use the native Parent issue field).
- The project item ID is stored in each file's `ghProjectItem:` frontmatter; edit
  with `gh project item-edit --project-id <node> --id <PVTI> --field-id … `.
- Requires the `project` scope on the `gh` token (added by the user 2026-09-17).

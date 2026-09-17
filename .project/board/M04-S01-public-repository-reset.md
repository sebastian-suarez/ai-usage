---
id: M04-S01
type: story
title: Public repository with fresh history and hardening
status: done
priority: P1
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZf0"
github: "https://github.com/sebastian-suarez/ai-usage/issues/16"
---

Recreate `sebastian-suarez/ai-usage` as a public repository whose history starts
at the first public release, instead of exposing the private repo's iterative
history. The old repo is renamed to `ai-usage-archive` and its full history and
release DMGs are backed up locally before anything is deleted. The new repo gets
the settings a public project needs: workflow token read-only by default, manual
approval for workflow runs from fork PRs, private vulnerability reporting, no
wiki/projects, delete-branch-on-merge, a CI workflow that runs the unit tests on
every push and PR, and Dependabot for GitHub Actions.

- [x] Full history of the private repo is bundled locally and its releases downloaded before it is renamed/deleted
- [x] `sebastian-suarez/ai-usage` is public, with description, topics and homepage set
- [x] History starts at a single initial commit tagged `v1.0.0`; no secrets, PR links or personal emails in the tree
- [x] Workflow permissions are read-only by default, fork PRs require approval, private vulnerability reporting is on, SECURITY.md exists
- [x] `ci.yml` runs `scripts/release.sh test` on pushes to `main` and on pull requests; Dependabot watches GitHub Actions
- [x] The five release secrets are set on the new repo and the tagged release workflow produces the v1.0.0 DMG

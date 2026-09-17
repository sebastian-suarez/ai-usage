---
id: M04-S02
type: story
title: License and end-user README
status: done
priority: P1
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZjo"
github: "https://github.com/sebastian-suarez/ai-usage/issues/17"
---

A public repo without a license is unusable, and the current README opens with
"open in Xcode", which is the wrong first screen for someone who just wants the
app. Add an MIT license and rewrite the README for end users first: what it does,
a screenshot of the menu bar item and the panel (light and dark), how to install
(Homebrew and DMG), what must be signed in before first launch, and only then how
it works, how to build and how releases are cut. Internal board references and
the step-by-step release manual move out of the top-level narrative.

- [x] `LICENSE` contains the MIT license with the author's name and year
- [x] README leads with install instructions and screenshots; the Xcode steps sit under a building-from-source section
- [x] Screenshots of the panel exist in light and dark and switch with the reader's theme on GitHub
- [x] Architecture and release flow are shown as Mermaid diagrams; no internal item IDs are referenced

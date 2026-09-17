---
id: M04-S03
type: story
title: Homebrew cask
status: in-progress
priority: P2
notion: "3deea0aa-87b0-8192-af76-c6c176678983"
github: ""
parent: "[[M04-public-release]]"
---

Developers expect `brew install --cask`. Publish a personal tap
(`sebastian-suarez/homebrew-tap`) with an `ai-usage` cask that points at the DMG
of the latest GitHub release, verified by SHA-256, installs `AI usage.app` and
cleans up the app's preferences on `brew uninstall --zap`. The cask is updated by
hand per release until it's worth automating.

- [ ] `brew install --cask sebastian-suarez/tap/ai-usage` installs the current release
- [ ] The cask verifies the DMG's SHA-256 and declares `depends_on macos: ">= :sonoma"`
- [ ] `brew uninstall --zap` removes the app and its preferences domain
- [ ] The README's install section documents the Homebrew route

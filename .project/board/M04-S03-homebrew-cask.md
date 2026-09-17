---
id: M04-S03
type: story
title: Homebrew cask
status: done
priority: P2
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZnY"
github: "https://github.com/sebastian-suarez/ai-usage/issues/18"
---

Developers expect `brew install --cask`. Publish a personal tap
(`sebastian-suarez/homebrew-tap`) with an `ai-usage` cask that points at the DMG
of the latest GitHub release, verified by SHA-256, installs `AI usage.app` and
cleans up the app's preferences on `brew uninstall --zap`. The cask is updated by
hand per release until it's worth automating.

- [x] `brew install --cask sebastian-suarez/tap/ai-usage` installs the current release
- [x] The cask verifies the DMG's SHA-256 and declares `depends_on macos: :sonoma`
- [x] `brew uninstall --zap` removes the app and its preferences domain
- [x] The README's install section documents the Homebrew route

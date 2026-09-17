---
id: M02-S04
type: story
title: Lower deployment target to macOS 14
status: done
priority: P1
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZJI"
github: "https://github.com/sebastian-suarez/ai-usage/issues/10"
---

AI Usage 1.0.0 shipped with `MACOSX_DEPLOYMENT_TARGET = 26.5`, an Xcode default
nobody chose. It is a hard floor: anyone on an older macOS gets "requires a newer
version of macOS" and cannot open the app at all. In practice that excludes
everyone except users fully updated to the current macOS — which makes the signed,
notarized DMG close to undistributable.

Verified before planning: a Release build at `MACOSX_DEPLOYMENT_TARGET = 13.0`
fails, because `UsageStore` uses `@Observable`/`ObservationRegistrar` (macOS 14+).
A build at `14.0` succeeds with **no code changes**. So macOS 14 (Sonoma) is the
real floor, and reaching it costs one setting.

Ship the result as 1.0.1 — the fix is worthless until there is a build carrying it.

- [x] `MACOSX_DEPLOYMENT_TARGET` is 14.0 for every target in the project
- [x] `MARKETING_VERSION` is 1.0.1 across all targets
- [x] Unit tests pass and a Release build succeeds at the new floor
- [x] `scripts/release.sh 1.0.1` produces a signed, notarized, stapled DMG
- [x] The built app's `LSMinimumSystemVersion` reads 14.0, proving the floor actually changed

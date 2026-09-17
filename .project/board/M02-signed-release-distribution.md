---
id: M02
type: milestone
title: Signed release distribution
status: done
priority: P1
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZPU"
github: "https://github.com/sebastian-suarez/ai-usage/issues/12"
---

Ship AI Usage as a real Mac app other people can install: a Developer ID-signed,
notarized and stapled build, packaged as a DMG, published as a GitHub release.
Today the app only runs from Xcode — Gatekeeper would block any copy handed to
someone else. The release path is written as a script that works on this Mac
first, then wired into CI so tagging a version is enough to cut a release.

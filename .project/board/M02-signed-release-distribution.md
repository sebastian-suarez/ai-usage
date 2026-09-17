---
id: M02
type: milestone
title: Signed release distribution
status: done
priority: P1
notion: "3a4ea0aa-87b0-8105-9d64-d4ead353f7ec"
github: ""
---

Ship AI Usage as a real Mac app other people can install: a Developer ID-signed,
notarized and stapled build, packaged as a DMG, published as a GitHub release.
Today the app only runs from Xcode — Gatekeeper would block any copy handed to
someone else. The release path is written as a script that works on this Mac
first, then wired into CI so tagging a version is enough to cut a release.

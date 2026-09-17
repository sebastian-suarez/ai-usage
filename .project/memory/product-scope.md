# Product scope — menu bar limits tracker

Decided 2026-07-18: AI Usage is a macOS menu bar app that shows the percentage
used of one selected usage limit; clicking the menu bar item opens a panel with
all limits of that limit's provider. Claude and ChatGPT subscriptions only.

**Why:** the original idea (subscription/spend tracker with SwiftData) was
dropped — the user wants something very simple that answers "how much of my
limit is left?" at a glance. No spend tracking, no API-key metering, no other
providers. Keep future stories inside this scope unless the user widens it.

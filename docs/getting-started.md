---
id: START
parent: HOME
order: 1
type: reference
title: Getting started
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# START — Getting started

## Install and run

```sh
scripts/build-app.sh --install   # builds dist/ClaudeMon.app, copies it to ~/Applications, launches it
```

On first launch:

1. A gauge icon with two percentages (session · week) appears in the menu bar. There is no Dock icon.
2. macOS asks whether ClaudeMon may use the Keychain item **Claude Code-credentials**. Choose **Always Allow**. Without it the panel shows token usage and cost, but no plan limits.
3. Click the menu-bar item to open the panel. Open **Settings…** to set the billing day and plan price, and to turn on **Launch at login**.

The grant is tied to the app's ad-hoc code signature, so every rebuild asks again ([BUILD.2](build/packaging.md)).

## Prerequisites

- macOS 14 or later, and Xcode 16 or later (built here with Xcode 27 / Swift 6.4).
- Claude Code installed and logged in. The app reads its transcripts and its stored login; it needs nothing else.

## Terminal report

```sh
dist/claudemon-report --billing-day 15 --plan-price 100
```

It prints the same today, week and billing-month totals and the plan comparison ([F-12](features/app/f-012-terminal-report.md)).

## Data on disk

| Path | What |
|---|---|
| `~/Library/Application Support/ClaudeMon/usage-cache.json` | Every API call seen so far. History outlives Claude Code's transcript cleanup. |
| `~/Library/Application Support/ClaudeMon/pricing.json` | API list prices. Edit, then use **Reload prices** in Settings. |
| `UserDefaults` (`com.bogovich.ClaudeMon`) | Settings |

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |

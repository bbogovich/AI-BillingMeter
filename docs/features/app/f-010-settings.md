---
id: F-10
parent: FEAT
order: 10
type: feature
title: Settings
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# F-10 — Settings

## F-10 — Settings (base)

### What

R-CMUI-005 (the settings list), R-CMUI-006 (saved and applied immediately) and R-CMUI-010 (the window brought to front) at spec 1.0.0. They serve F-10.AC-1 (the list of settings) and F-10.AC-2 (changes take effect immediately and persist).

### How

```mermaid
flowchart LR
    B["Settings… button"] -->|openWindow(id: settings) + NSApp.activate| W["SettingsView (Form, grouped)"]
    W -->|"@Bindable"| M["AppModel properties"]
    M -->|didSet → save(_:_:)| U["UserDefaults"]
    M -->|observation| V["MenuContentView / MenuBarLabel re-render"]
```

| Setting | Property | Default |
|---|---|---|
| Billing month starts on day | `billingDay` | 1 |
| Monthly plan price (0 = detected) | `planPriceOverride` | 0 |
| Week starts | `weekStart` | plan's weekly reset |
| Fetch plan limits / refresh every N min | `fetchPlanLimits`, `planRefreshMinutes` | on, 5 |
| Menu bar shows | `menuBarStyle` | limits |
| Launch at login | `launchAtLogin` | off (F-11) |
| Edit / reload pricing.json, rescan, show data folder | actions | — |

### Where

| Requirement | File | Symbols |
|---|---|---|
| R-CMUI-005 | `Sources/ClaudeMon/SettingsView.swift` | SettingsView |
| R-CMUI-006 | `Sources/ClaudeMon/AppModel.swift` | AppModel.save(_:_:), billingDay, weekStart, planPriceOverride, fetchPlanLimits, menuBarStyle |
| R-CMUI-010 | `Sources/ClaudeMon/MenuContentView.swift` | openWindow, activate |
| R-CMUI-010 | `Sources/ClaudeMon/ClaudeMonApp.swift` | ClaudeMonApp |

### Why

- **A `Window` scene with `openWindow` plus `NSApp.activate`,** not `Settings`/`SettingsLink`, because an agent app (`LSUIElement`) otherwise opens the window behind the frontmost app.
- **`UserDefaults` via `didSet`** on `@Observable` properties: the smallest persistence that applies changes on the spot.

### How to test

R-CMUI-005, -006 and -010 cases are `manual` and not yet executed as recorded verification items (see [DEV](../../deviations/index.md) P-2). Observed in use: screenshot `scr-app-2-settings.png`.

### Limits

- The plan price field accepts any number, including negatives; values ≤ 0 mean "detected".

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): base section |

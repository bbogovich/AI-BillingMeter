---
id: RV-1
parent: REV
order: 1
type: record
title: "Review: COR-1 panel anchoring"
spec_version: 1.1.0
status: approved
updated: 2026-10-15
---

# RV-1 — Review: COR-1 panel anchoring (ClaudeMon)

| | |
|---|---|
| Review item | RV-1 (retroactive record) |
| Work item | COR-1 |
| Reviewer | human:brian (owner; no separate architect review) |
| Spec | ClaudeMon-Definition specification 1.1.0 (R-CMUI-008) |
| Commits | 1: `4a42147`. There is no `Work-Item` trailer; the commit is identified by hand. |
| Outcome | Accepted in use. No explicit approval was recorded: after the fix, the owner's next message moved to another topic (SRC-3). |

## Change map

### R-CMUI-008 Panel stays anchored under the menu bar
+ WindowFitter                  Sources/ClaudeMon/WindowFitter.swift
+ WindowReader                  Sources/ClaudeMon/WindowFitter.swift
+ View.fitsMenuBarWindow()      Sources/ClaudeMon/WindowFitter.swift
~ MenuContentView.body          Sources/ClaudeMon/MenuContentView.swift
  tests: none automated; R-CMUI-008.T1 executed by script (see TEST)

## Agent's notes

- The owner's description ("dialog is no longer anchored… shifted down") suggested a moving window. Measurement showed the window frame never changed (895 pt on every tab) and the shorter content was centred inside it. The fix resizes the window rather than repositioning it.
- Root cause: a `.window`-style `MenuBarExtra` never shrinks its window. A vault note was written.

## Checklist (not performed)

- [ ] R-CMUI-008 built as specified · tests meaningful · annotation right

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-10-15 | v1.0.1 (4a42147): record written retroactively |

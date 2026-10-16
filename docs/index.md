---
id: HOME
order: 0
type: overview
title: ClaudeMon implementation
spec_version: 1.3.0
status: approved
updated: 2026-10-15
---

# HOME — ClaudeMon implementation

ClaudeMon is a native macOS menu-bar app. It shows how much of a Claude plan's session and weekly limits is left. It also shows Claude Code token consumption for today, the week and the billing month, and what that usage would have cost at API list prices. This site documents the app **as built**: what each feature does in the code, where it lives, why it was built that way, and how to test it.

| | |
|---|---|
| Implementation repository | `ClaudeMon` (code on `main`; this site on the `docs` branch) |
| Targets | ClaudeMon-Definition specification **1.3.0** · definition **1.2.0** |
| Latest release | [v1.2.0](releases/v1.2.0.md) (commit `736d417`) |
| Platform | macOS 14 or later, Apple silicon and Intel; Swift 6, SwiftUI, Swift Charts |

!!! note "Retroactive case study"
    The app was built in one Claude Code session on 2026-10-15, before any process artifacts existed. This site was written afterwards, against the real code and the real session record, as a case study of the SpecItOut rev 9 lifecycle. Where a process step did not happen, the page says so instead of inventing it. See [Deviations](deviations/index.md).

## Where to start

- **Use it or build it:** [Getting started](getting-started.md), then [Build](build/index.md).
- **What each feature does in the code:** [Features](features/index.md). There is one page per feature, with What, How, Where, Why, How to test and Limits.
- **How it is put together:** [Architecture](architecture/index.md) and the generated [Code map](code-map.md).
- **What is verified:** [Testing](testing.md) and [Implementation status](implementation-status.md).
- **What shipped when:** [Releases](releases/index.md) and [Reviews](reviews/index.md).

## Upstream

- The definition and the specification live in one consolidated repository, `../ClaudeMon-Definition`. The definition is its `docs/` tree; the specification is `docs/spec/`.
- Requirement IDs (`R-CM…`) on this site refer to specification 1.3.0. Feature IDs (`F-n`) refer to definition 1.2.0. From outside that repository they are written `ClaudeMon-Definition:F-n`.

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.3.0 | 2026-10-15 | v1.2.0 (736d417): pins moved to spec 1.3.0 / definition 1.2.0 |
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial site (written retroactively) |

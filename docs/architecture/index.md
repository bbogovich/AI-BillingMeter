---
id: ARCH
parent: HOME
order: 6
type: index
title: Architecture
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# ARCH — Architecture

## System overview

```mermaid
flowchart LR
    subgraph Mac["Owner's Mac"]
        subgraph App["ClaudeMon.app (menu-bar agent)"]
            UI["SwiftUI: MenuBarExtra panel,<br/>Settings window"]
            AM["AppModel (@MainActor, @Observable)"]
            CORE["ClaudeMonCore"]
        end
        CLI["claudemon-report"]
        T[("~/.claude/projects/**/*.jsonl<br/>(Claude Code transcripts)")]
        AS[("~/Library/Application Support/ClaudeMon<br/>usage-cache.json · pricing.json")]
        UD[("UserDefaults")]
        KC[("Login Keychain<br/>Claude Code-credentials")]
        SM["ServiceManagement<br/>(login item)"]
    end
    API["api.anthropic.com<br/>GET /api/oauth/usage"]
    UI <--> AM
    AM --> CORE
    CLI --> CORE
    CORE -->|read, incremental| T
    CORE <-->|read/write| AS
    AM <--> UD
    CORE -->|read only| KC
    CORE -->|HTTPS| API
    AM --> SM
```

| Component | Process | Data stores | External |
|---|---|---|---|
| `ClaudeMonCore` (library) | in-process | `usage-cache.json`, `pricing.json` | Keychain (read), `api.anthropic.com` |
| `ClaudeMon` (app) | menu-bar agent, one process | `UserDefaults` | ServiceManagement |
| `claudemon-report` (CLI) | short-lived | the app's `usage-cache.json`, or a temporary one | — |

The app's state flows one way: `TranscriptStore` and `PlanUsageClient` feed `AppModel`, which holds the entries and plan status; views compute reports from it on demand through `ReportBuilder`. There is no database and no background daemon.

## Pages

<!-- generated:children -->
| ID | Title | Status |
|---|---|---|
| ARCH.1 | [Transcript accounting (core)](core-transcripts.md) | approved |
| ARCH.2 | [Plan-limit client](plan-limits.md) | approved |
| ARCH.3 | [Reports and pricing](reports-pricing.md) | approved |
| ARCH.4 | [App and UI](app-ui.md) | approved |
| ARCH.5 | [Terminal report](cli.md) | approved |
| ARCH.6 | [Data model](data-model.md) | approved |
| ARCH.7 | [Dependencies](dependencies.md) | approved |
<!-- /generated -->

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |

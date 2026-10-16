---
id: ARCH.7
parent: ARCH
order: 7
type: architecture
title: Dependencies
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# ARCH.7 — Dependencies

ClaudeMon has **no third-party dependencies** (DEC-4, the owner's standing rule; ADR-1). `Package.swift` declares no packages. Every framework below ships with macOS and Xcode.

## Architecture Overview

### Product (shipped in the app)

| Framework | Used for | Complexity it saves | Stability | Tree | Share used | Licence |
|---|---|---|---|---|---|---|
| SwiftUI | `MenuBarExtra`, panel, settings | The whole UI layer | Apple, OS-versioned | None (system) | Large | Apple SDK |
| Swift Charts | Stacked bars, selection | Chart layout and axes | Apple, macOS 13+ | None | Small (BarMark, RuleMark) | Apple SDK |
| Foundation | JSON, files, URLSession, dates | — | Apple | None | Large | Apple SDK |
| Security | `SecItemCopyMatching` (read the Claude Code login) | Keychain access | Apple | None | One call | Apple SDK |
| ServiceManagement | `SMAppService.mainApp` login item | Login items | Apple, macOS 13+ | None | One API | Apple SDK |
| AppKit | `NSWindow` resizing (COR-1), colours, workspace | — | Apple | None | Small | Apple SDK |
| Observation | `@Observable` model | Change tracking | Apple, macOS 14+ | None | One macro | Apple SDK |

### Development only

| Tool | Used for | Evaluation |
|---|---|---|
| Swift Testing | Unit and integration tests | Ships with Xcode; no package |
| Core Graphics + `iconutil` | `scripts/make-icon.swift` | System tools |
| MkDocs 1.6 + Material 9.x (docs branch, `requirements-docs.txt`) | Building this site | Third-party Python. The SpecItOut process mandates it (all sites are MkDocs Material). Pinned below 2.0 (MkDocs 2 breaks Material). Large transitive tree (Jinja2, Markdown, pymdown-extensions, …), but build-time only and never shipped. Licences: BSD-2 (MkDocs), MIT (Material). |
| Python 3 standard library | `scripts/sitegen.py` (nav, generated sections, checks) | No packages |

## Key Symbols

`Package.swift`: `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v5]`, targets `ClaudeMonCore`, `ClaudeMon`, `claudemon-report`, `ClaudeMonCoreTests`. No `dependencies:` key.

## API Reference

The undocumented `GET https://api.anthropic.com/api/oauth/usage` is a runtime dependency, not a package. It is evaluated in ADR-3: accepted risk, because nothing else exposes plan limits.

## Debugging

`xcrun swift package show-dependencies` prints an empty tree.

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |

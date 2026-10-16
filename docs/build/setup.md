---
id: BUILD.1
parent: BUILD
order: 1
type: reference
title: Toolchain setup
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# BUILD.1 — Toolchain setup

The project is a SwiftPM package (`Package.swift`, tools version 6.0, Swift 5 language mode, macOS 14 minimum) with three products:

| Target | Kind | Contents |
|---|---|---|
| `ClaudeMonCore` | library | Transcript parsing, pricing, reports, the plan-limit client. No UI. |
| `ClaudeMon` | executable | The SwiftUI menu-bar app |
| `claudemon-report` | executable | The terminal report |
| `ClaudeMonCoreTests` | tests | Swift Testing suites for `ClaudeMonCore` |

There is no Xcode project ([ADR-1](../architecture/dependencies.md)).

## Always use `xcrun swift`

```sh
xcrun swift build            # debug
xcrun swift build -c release # release; products in .build/out/Products/Release (Xcode 27 layout)
xcrun swift test             # all suites
```

!!! warning "A bare `swift` can pick the wrong toolchain"
    On the build machine, `~/.swiftly/bin/swift` (Swift 6.3.2) comes before Xcode's toolchain on `PATH`. It cannot build against the macOS 27 SDK. It fails with `unknown argument: '-target-arch-variant'` and then `cannot find type 'Date' in scope`. `xcrun swift` always picks the toolchain that matches the selected Xcode (here Swift 6.4). The spec records this as ADR-5.

Other notes:

- Xcode 27's SwiftPM puts release products in `.build/out/Products/Release`. Ask `xcrun swift build -c release --show-bin-path` rather than hard-coding the path.
- Passing two `--product` flags built only one product. Build everything with a plain `xcrun swift build -c release`.

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |

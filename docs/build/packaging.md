---
id: BUILD.2
parent: BUILD
order: 2
type: reference
title: Packaging, signing and the icon
spec_version: 1.3.0
status: approved
updated: 2026-10-15
---

# BUILD.2 — Packaging, signing and the icon

`scripts/build-app.sh` turns the SwiftPM products into an app bundle:

```mermaid
flowchart LR
    B["xcrun swift build -c release"] --> A["dist/ClaudeMon.app/Contents/MacOS/ClaudeMon"]
    P["Resources/Info.plist"] --> A
    I["Resources/AppIcon.icns"] --> A
    B --> R["dist/claudemon-report"]
    A --> S["codesign --sign - (ad hoc)"]
    S -->|--install| H["~/Applications/ClaudeMon.app, relaunched"]
```

| Step | Detail |
|---|---|
| Info.plist | `LSUIElement = true` (menu bar only, no Dock icon, R-CMUI-001). Bundle id `com.bogovich.ClaudeMon`. `CFBundleIconFile = AppIcon`. Version 1.0.0 (see [Deviations](../deviations/index.md)). |
| Signing | Ad hoc (`codesign --force --sign -`). The designated requirement is the binary's cdhash, so it changes with every build. |
| Install | `--install` kills the running copy, copies the bundle to `~/Applications`, waits one second, then runs `open`. Without the pause, `open` sometimes failed with LaunchServices error -600. |

## Keychain prompt after each rebuild

macOS records the **Always Allow** grant for the `Claude Code-credentials` item against the app's designated requirement. With ad-hoc signing that requirement is the cdhash, so each rebuild is a new app to the Keychain and the prompt returns. The grant persists across launches, logouts and restarts of the same build.

The owner was offered two mitigations: an in-memory token cache, and signing with the Apple Development identity. The owner declined both: "if always allow will persist into new sessions then it's fine as is" (definition SRC-3).

## App icon (F-13, F-13.CR-1)

The icon is drawn in code. No image assets are checked in apart from the generated outputs.

```sh
xcrun swift scripts/make-icon.swift   # writes Resources/AppIcon.icns and Resources/AppIcon-1024.png
```

`drawIcon(in:size:)` paints on the 1024-point macOS icon grid. `png(size:)` renders each size of the iconset, and `iconutil` packs them. See [F-13](../features/app/f-013-app-icon.md).

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.3.0 | 2026-10-15 | v1.2.0 (736d417): speedometer radius 231 (F-13.CR-1) |
| 1.2.0 | 2026-10-15 | v1.1.0 (1618231): icon generation and `AppIcon.icns`; relaunch pause |
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |

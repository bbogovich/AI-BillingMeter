# AI Billing Meter

A native macOS menu-bar and Dock app that shows Claude Code usage and what it would cost at API rates
(formerly ClaudeMon; the first launch moves ClaudeMon's history and settings over):

- **Plan limits**: the 5-hour session limit and the weekly limits, with % used and remaining and reset times. These are the same numbers claude.ai and `/usage` show.
- **Token consumption**: today (per hour), this week (per day), the billing month (per day) and all history (per month; scrolls sideways past twelve months). Shown as text totals (input / output / cache write / cache read) and as stacked charts by model family.
- **Per-project totals, kept permanently**: each project is the directory a Claude Code session was started in, so unrelated folders with the same name stay apart. History outlives Claude Code's transcript cleanup; months older than the detail window are kept as weekly totals per model and project.
- **Cost**: what the same usage would have cost at Anthropic API list prices, compared with the flat plan price. Includes a projection for the whole billing month.

No third-party dependencies. It uses AppKit, SwiftUI, Swift Charts and ServiceManagement, and reads the Claude Code login through `/usr/bin/security`.

## Build and install

**In Xcode:** open `AIBillingMeter.xcodeproj` and run the **AIBillingMeterApp** scheme (⌘R). ⌘U runs the unit tests.
The project has three targets: the app, the `billing-meter` tool, and the tests. All three link
`BillingMeterCore` from this repository's Swift package. Source folders are synchronized, so new files under
`Sources/AIBillingMeter`, `Sources/billing-meter` and `Tests/BillingMeterCoreTests` are picked up without editing the
project. Signing is "Sign to Run Locally".

**From the terminal:**

```sh
scripts/build-app.sh            # builds dist/AI Billing Meter.app and dist/billing-meter
scripts/build-app.sh --install  # also copies to ~/Applications and launches it
xcrun swift test                # unit tests
```

Use `xcrun swift`, not a bare `swift`. If a swiftly toolchain comes earlier on `PATH` and doesn't match the Xcode SDK, the build fails with `unknown argument: '-target-arch-variant'`.

Turn on **Settings → Launch at login** to have it start with macOS.

`dist/billing-meter` prints the same totals in the terminal, for example `billing-meter --billing-day 15 --plan-price 100`. The all-time section lists every project's total; `--projects` adds project lists to the other periods.

## Where the numbers come from

| Data | Source |
|---|---|
| Tokens, models, projects | Claude Code transcripts in `~/.claude/projects/**/*.jsonl` (or `$CLAUDE_CONFIG_DIR`), read incrementally |
| Plan limits, plan tier | `GET https://api.anthropic.com/api/oauth/usage`, using the OAuth login Claude Code keeps in the Keychain (`Claude Code-credentials`) |
| API prices | `~/Library/Application Support/AI Billing Meter/pricing.json`, which you can edit (defaults are list prices as of 2026-10-06) |

Things to know:

- **There is no daily quota.** Max plans limit a rolling 5-hour session and a 7-day window. "Today" shows token totals; the limits section shows the session and weekly windows.
- **Duplicate transcript lines are merged.** Claude Code writes several lines per API response. Later lines can carry larger `output_tokens`, so entries are keyed on `message.id + requestId` and merged with the maximum of each field.
- **History is kept.** Claude Code deletes old transcripts (30 days by default). AI Billing Meter caches every call it has seen in `usage-cache.json`, so a billing month stays complete.
- **Limits include everything; tokens only include Claude Code.** claude.ai chat, Cowork and other devices count toward plan limits but leave no local transcript.
- **The token is only read.** It is never refreshed, because OAuth refresh tokens rotate and refreshing would sign Claude Code out. If it expires, run `claude` once. macOS asks for Keychain access on first launch and again after each rebuild, because the ad-hoc signature changes.
- **`/api/oauth/usage` is an internal endpoint** used by Claude Code and is undocumented. If it changes, the limits section shows an error and everything else keeps working.

## Settings

- Billing day of month
- Plan price (0 = list price of the detected plan: Pro $20, Max 5x $100, Max 20x $200)
- Week start (plan's weekly reset, Monday or Sunday)
- Plan-limit refresh interval
- What the menu bar shows: limits, tokens today, cost today, or the icon only
- Launch at login

## Lifecycle artifacts

AI Billing Meter is a worked case study for the SpecItOut process (proposal rev 9). Its definition, design and
specification live in `../ClaudeMon-Definition`, and the implementation documentation site (features as built,
architecture, code map, testing, reviews, releases) lives on this repository's `docs` branch.
`.specitout/sdd.json` pins definition 1.2.0 and spec 1.3.0.

## Layout

```
Sources/BillingMeterCore     parsing, pricing, reports, plan-limit client (tested)
Sources/AIBillingMeter         Menu-bar + Dock app (AppKit status item, SwiftUI views; `--snapshot <dir>` renders the panel to PNGs)
Sources/billing-meter  terminal report
Tests/BillingMeterCoreTests
scripts/build-app.sh
scripts/make-icon.swift   draws Resources/AppIcon.icns (run: xcrun swift scripts/make-icon.swift)
```

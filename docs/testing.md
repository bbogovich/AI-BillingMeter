---
id: TEST
parent: HOME
order: 8
type: reference
title: Testing
spec_version: 1.3.0
status: approved
updated: 2026-10-15
---

# TEST — Testing

```sh
xcrun swift test                       # 15 tests in 5 suites, about 0.01 s
xcrun swift test --filter PricingTests # one suite
```

All 15 passed at every release (v1.0.0 to v1.2.0). Tests live in `Tests/ClaudeMonCoreTests/ClaudeMonCoreTests.swift` and use Swift Testing. They cover `ClaudeMonCore` only; the app target has no tests.

## Automated cases

Each spec test case that an automated test implements. One test can implement several cases.

| Case | Level | Test (Suite.function) | Feature |
|---|---|---|---|
| R-CMUSE-002.T1 | unit | ParsingTests.parsesUsageLine | F-3 |
| R-CMUSE-002.T2 | unit | ParsingTests.ignoresNonUsageAndSyntheticLines | F-3 |
| R-CMUSE-006.T1 | unit | ParsingTests.parsesUsageLine (project = "MyProj") | F-3 |
| R-CMUSE-005.T1 | unit | ParsingTests.missingTTLBreakdownCountsAsFiveMinute | F-3 |
| R-CMUSE-004.T1 | unit | ParsingTests.duplicatesMergeWithMaxPerField | F-3 |
| R-CMUSE-003.T1 | integration | StoreTests.incrementalScanHandlesPartialLinesAndDuplicates (partial line read next time) | F-3 |
| R-CMUSE-008.T1 | integration | StoreTests.incrementalScanHandlesPartialLinesAndDuplicates (fresh store restores after transcript deleted) | F-3 |
| R-CMCST-001.T1 | unit | PricingTests.datedIdsMatchByLongestPrefix | F-7 |
| R-CMCST-002.T1 | unit | PricingTests.opus55Cost | F-7 |
| R-CMCST-003.T1 | unit | PricingTests.haiku55LongContextTier | F-7 |
| R-CMCST-004.T1 | unit | PricingTests.fastModeDoublesPrice | F-7 |
| R-CMCST-007.T1 | unit | ReportTests.reportTotalsOnlyIncludeThePeriod (unpricedTokens == 7) | F-7 |
| R-CMCST-009.T1 | unit | ReportTests.billingProjectionScalesByElapsedTime | F-8 |
| R-CMCST-011.T1 | unit | ReportTests.billingProjectionScalesByElapsedTime (savings −60) | F-8 |
| R-CMRPT-002.T1 | unit | ReportTests.weekFollowsPlanResetWhenKnown (plan window) | F-4 |
| R-CMRPT-002.T2 | unit | ReportTests.weekFollowsPlanResetWhenKnown (stale window → calendar week) | F-4 |
| R-CMRPT-003.T1 | unit | ReportTests.billingIntervalBeforeAndAfterBillingDay | F-4 |
| R-CMRPT-004.T1 | unit | ReportTests.reportTotalsOnlyIncludeThePeriod | F-4 |
| R-CMRPT-007.T1 | unit | ReportTests.reportTotalsOnlyIncludeThePeriod (families Opus, Sonnet, Other) | F-6 |
| R-CMLIM-004.T1 | unit | PlanUsageTests.parsesLimitsArray | F-1 |
| R-CMLIM-008.T1 | unit | PlanUsageTests.parsesLimitsArray (Max 5x, $100) | F-1, F-8 |
| R-CMLIM-005.T1 | unit | PlanUsageTests.fallsBackToLegacyFields | F-1 |

The tests carry no `trace: R-….Tn` comments yet; this table is the mapping ([DEV](deviations/index.md) D-3). Edge tests (`edge: R-…`) do not exist yet. Changed-code coverage has not been measured.

## Executed measurement and UI cases

These were run once during the build session. Each is recorded with its evidence, not as a repeatable test.

| Case | Level | Evidence (2026-10-15) | Feature |
|---|---|---|---|
| R-CMRPT-005.T1 | measurement | `claudemon-report --no-cache` against an independent Python recount: month 3,378 vs 3,381 calls, $339.40 vs $339.54. The difference is the calls made between the two runs. | F-4, F-12 |
| R-CMUSE-003.T2 | measurement | Cold scan of 529 MB / 203 transcripts in 3.9 s (release build) | F-3 |
| R-CMUI-008.T1 | ui | Scripted System Events: window height 567 → 699 → 567 pt across Today → Billing month → Today, top edge fixed at y = 35. Before the fix the height stayed at 895 and the content was centred. | F-9 (COR-1) |
| R-CMLIM-003.T1 | integration | A live call returned 200 with `five_hour`, `seven_day` and `limits` (the owner's Max 5x login) | F-1 |
| R-CMUI-012.T1 | ui | `NSWorkspace` icon rendering of the installed app shows the icon full size, not shrunk onto a grey plate | F-13 |

## Specified, not yet executed

These spec test cases (ClaudeMon-Definition spec 1.3.0) have **not** been run as recorded verification items. Some behaviour was observed in normal use, but no item records a pass, so none is claimed here.

| Case | Level | Scenario | Feature |
|---|---|---|---|
| R-CMCLI-001.T1 | manual | plan price given | F-12 |
| R-CMCLI-001.T2 | manual | unknown option | F-12 |
| R-CMCLI-002.T1 | manual | matches the panel | F-12 |
| R-CMCLI-003.T1 | manual | app cache untouched | F-12 |
| R-CMCST-005.T1 | manual | three searches in fast mode | F-7 |
| R-CMCST-006.T1 | manual | edit and reload | F-7 |
| R-CMCST-006.T2 | manual | malformed file kept | F-7 |
| R-CMCST-008.T1 | ui | mid-month | F-8 |
| R-CMCST-010.T1 | manual | override | F-8, F-10 |
| R-CMCST-011.T2 | ui | plan wins | F-8 |
| R-CMLIM-001.T1 | manual | stored login present | F-1 |
| R-CMLIM-001.T2 | manual | no stored login | F-1 |
| R-CMLIM-002.T1 | manual | expired token | F-1 |
| R-CMLIM-002.T2 | manual | the Keychain item is left unchanged | F-1 |
| R-CMLIM-006.T1 | manual | server error | F-1 |
| R-CMLIM-007.T1 | manual | refresh button | F-1, F-10 |
| R-CMLIM-007.T2 | manual | fetching disabled | F-1, F-10 |
| R-CMLIM-009.T1 | ui | session limit row | F-1 |
| R-CMLIM-009.T2 | ui | weekly limit several days away | F-1 |
| R-CMLIM-010.T1 | ui | warning threshold | F-1 |
| R-CMLIM-010.T2 | ui | icon present at every status | F-1 |
| R-CMLIM-011.T1 | manual | offline | F-1 |
| R-CMRPT-001.T1 | manual | late evening | F-4 |
| R-CMRPT-006.T1 | ui | switch to projects | F-6 |
| R-CMRPT-008.T1 | ui | plan week starting at 10 PM | F-5 |
| R-CMRPT-009.T1 | ui | only Opus used | F-5 |
| R-CMRPT-010.T1 | ui | switch to cost | F-5 |
| R-CMRPT-011.T1 | ui | hover an hour | F-5 |
| R-CMUI-001.T1 | manual | launched | F-9 |
| R-CMUI-002.T1 | ui | default readout | F-2 |
| R-CMUI-002.T2 | ui | limits unavailable | F-2 |
| R-CMUI-003.T1 | ui | billing month tab | F-4, F-9 |
| R-CMUI-003.T2 | manual | quit | F-4, F-9 |
| R-CMUI-004.T1 | ui | width across tabs | F-9 |
| R-CMUI-009.T1 | manual | footer time updates | F-1, F-3 |
| R-CMUI-005.T1 | ui | billing day range | F-10 |
| R-CMUI-006.T1 | manual | menu bar style | F-10 |
| R-CMUI-007.T1 | manual | enable | F-11 |
| R-CMUI-010.T1 | ui | from the panel | F-9, F-10 |
| R-CMUI-011.T1 | manual | icon in Finder | F-13 |
| R-CMUI-013.T1 | manual | dial size | F-13 |
| R-CMUSE-001.T1 | manual | nested subagent transcript | F-3 |
| R-CMUSE-004.T2 | integration | duplicates across a rescan | F-3 |
| R-CMUSE-007.T1 | manual | relaunch uses the cache | F-3 |
| R-CMUSE-009.T1 | manual | rescan after a transcript was deleted | F-3, F-10 |
| R-CMUSE-010.T1 | manual | usage from a running session | F-3 |

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.3.0 | 2026-10-15 | v1.2.0 (736d417): R-CMUI-013 listed |
| 1.2.0 | 2026-10-15 | v1.1.0 (1618231): R-CMUI-011, -012 |
| 1.1.0 | 2026-10-15 | v1.0.1 (4a42147): R-CMUI-008.T1 evidence |
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial catalogue |

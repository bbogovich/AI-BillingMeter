---
id: MAP
parent: HOME
order: 7
type: reference
title: Code map
spec_version: 1.3.0
status: approved
updated: 2026-10-15
---

# MAP — Code map

Module → symbols → requirements → features. It is generated from the Where tables on the [feature pages](features/index.md) by `scripts/sitegen.py generate`; do not edit the table by hand. `sitegen.py check --code-root <ClaudeMon checkout>` reports any file or symbol listed here that no longer exists.

The code carries no `trace:` annotations yet ([DEV](deviations/index.md) D-3), so this map is the only link from code to requirements.

<!-- generated:code-map -->
| Module | Symbols | Requirements | Features |
|---|---|---|---|
| `Resources/Info.plist` | CFBundleIconFile, LSUIElement | R-CMUI-001, R-CMUI-012 | F-9, F-13 |
| `Sources/ClaudeMon/AppModel.swift` | AppModel.effectivePlanPrice, AppModel.launchAtLogin, AppModel.menuBarText, AppModel.refreshAll(), AppModel.refreshPlan(), AppModel.refreshTranscripts(full:), AppModel.reloadPrices(), AppModel.save(_:_:), AppModel.start(), MenuBarStyle, SMAppService, billingDay, fetchPlanLimits, menuBarStyle, planPriceOverride, planRefreshMinutes, pricesURL, sessionLimit, weekStart, weeklyLimit | R-CMCST-006, R-CMCST-010, R-CMLIM-007, R-CMUI-002, R-CMUI-006, R-CMUI-007, R-CMUI-009, R-CMUSE-010 | F-1, F-2, F-3, F-7, F-8, F-9, F-10, F-11 |
| `Sources/ClaudeMon/ClaudeMonApp.swift` | ClaudeMonApp, MenuBarExtra, MenuBarLabel | R-CMUI-001, R-CMUI-002, R-CMUI-010 | F-2, F-9, F-10 |
| `Sources/ClaudeMon/MenuContentView.swift` | BillingSection, BreakdownSection, LimitRow, MenuContentView, MenuContentView.periodHeader(_:), PlanLimitsSection, TotalsGrid, activate, fitsMenuBarWindow, openWindow | R-CMCST-011, R-CMLIM-009, R-CMLIM-011, R-CMRPT-005, R-CMRPT-006, R-CMUI-003, R-CMUI-004, R-CMUI-008, R-CMUI-010, R-CMUSE-010 | F-1, F-3, F-4, F-6, F-8, F-9, F-10 |
| `Sources/ClaudeMon/SettingsView.swift` | SettingsView | R-CMUI-005, R-CMUI-007 | F-10, F-11 |
| `Sources/ClaudeMon/Theme.swift` | Format.percent(_:), Format.resetText(_:), Theme.color(forFamily:), Theme.critical, Theme.familyColors, Theme.familyOrder, Theme.good, Theme.status(forPercentUsed:), Theme.warning | R-CMLIM-009, R-CMLIM-010, R-CMRPT-009 | F-1, F-5 |
| `Sources/ClaudeMon/UsageChart.swift` | ChartMetric, UsageChart, UsageChart.tooltip(for:), chartForegroundStyleScale, chartXSelection | R-CMRPT-009, R-CMRPT-010, R-CMRPT-011 | F-5 |
| `Sources/ClaudeMon/WindowFitter.swift` | WindowFitter, WindowReader, fitsMenuBarWindow(), resize(to:) | R-CMUI-008 | F-9 |
| `Sources/ClaudeMonCore/PlanUsage.swift` | Plan.displayName, Plan.listMonthlyPrice, PlanLimit, PlanStatus.weeklyWindowStart, PlanUsageClient.endpoint, PlanUsageClient.fetch(), PlanUsageClient.parse(_:plan:fetchedAt:), PlanUsageClient.readCredentials(), PlanUsageClient.title(kind:scope:), PlanUsageError.errorDescription, PlanUsageError.loginExpired, keychainService | R-CMLIM-001, R-CMLIM-002, R-CMLIM-003, R-CMLIM-004, R-CMLIM-005, R-CMLIM-006, R-CMLIM-008, R-CMRPT-002 | F-1, F-4 |
| `Sources/ClaudeMonCore/Pricing.swift` | ModelPrice.cacheWrite1hMultiplier, ModelPrice.cacheWrite5mMultiplier, ModelPrice.fastMultiplier, ModelPrice.longContextThreshold, PriceTable.cost(of:), PriceTable.loadOrInstall(at:), PriceTable.price(for:), PriceTable.standard, PriceTable.webSearchPerThousand | R-CMCST-001, R-CMCST-002, R-CMCST-003, R-CMCST-004, R-CMCST-005, R-CMCST-006 | F-7 |
| `Sources/ClaudeMonCore/Reports.swift` | BillingComparison.apiCostToDate, BillingComparison.elapsedFraction, BillingComparison.projectedApiCost, BillingComparison.projectedSavings, BillingComparison.valueMultipleToDate, BreakdownRow, PeriodReport.bucketUnit, PeriodReport.byModel, PeriodReport.byProject, PeriodReport.chartDomain, ReportBuilder.billingComparison(entries:now:planPrice:), ReportBuilder.billingInterval(now:), ReportBuilder.family(of:), ReportBuilder.interval(for:now:), ReportBuilder.report(_:entries:now:), ReportBuilder.weekInterval(now:), TokenTotals, TokenTotals.add(_:cost:), TokenTotals.unpricedTokens, UsageBucket, WeekStart, billingDay | R-CMCST-007, R-CMCST-008, R-CMCST-009, R-CMCST-011, R-CMRPT-001, R-CMRPT-002, R-CMRPT-003, R-CMRPT-004, R-CMRPT-005, R-CMRPT-006, R-CMRPT-007, R-CMRPT-008 | F-4, F-5, F-6, F-7, F-8 |
| `Sources/ClaudeMonCore/TranscriptStore.swift` | Cache, FileState, TranscriptStore.defaultRoots(), TranscriptStore.loadCache(), TranscriptStore.rescanAll(), TranscriptStore.saveCache(), TranscriptStore.scan(_:), transcriptFiles() | R-CMUSE-001, R-CMUSE-003, R-CMUSE-004, R-CMUSE-007, R-CMUSE-008, R-CMUSE-009 | F-3 |
| `Sources/ClaudeMonCore/UsageEntry.swift` | TranscriptLine.parse(_:fallbackProject:), UsageEntry.cacheWrite1hTokens, UsageEntry.cacheWrite5mTokens, UsageEntry.merged(with:), UsageEntry.project | R-CMUSE-002, R-CMUSE-004, R-CMUSE-005, R-CMUSE-006 | F-3 |
| `Sources/claudemon-report/main.swift` | --billing-day, --no-cache, --plan-price, PriceTable.loadOrInstall, ReportBuilder, TranscriptStore, removeItem, useCache | R-CMCLI-001, R-CMCLI-002, R-CMCLI-003 | F-12 |
| `scripts/build-app.sh` | AppIcon.icns | R-CMUI-012 | F-13 |
| `scripts/make-icon.swift` | color(_:_:), drawIcon(in:size:), iconutil, png(size:) | R-CMUI-011, R-CMUI-012, R-CMUI-013 | F-13 |
<!-- /generated -->

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.3.0 | 2026-10-15 | v1.2.0 (736d417): regenerated (R-CMUI-013) |
| 1.2.0 | 2026-10-15 | v1.1.0 (1618231): regenerated (icon) |
| 1.1.0 | 2026-10-15 | v1.0.1 (4a42147): regenerated (WindowFitter) |
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial map |

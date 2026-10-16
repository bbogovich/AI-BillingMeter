---
id: F-7
parent: FEAT
order: 7
type: feature
title: API-equivalent cost
spec_version: 1.0.0
status: approved
updated: 2026-10-15
---

# F-7 — API-equivalent cost

## F-7 — API-equivalent cost (base)

### What

R-CMCST-001 to R-CMCST-007 (pricing) and the pricing file format FMT.1, at spec 1.0.0. They serve F-7.AC-1 (per-model list price including cache writes and reads, fast mode and web search), F-7.AC-2 (prices editable without rebuilding) and F-7.AC-3 (unpriced usage reported, not costed at zero).

### How

```mermaid
flowchart TD
    E["UsageEntry"] --> P["PriceTable.price(for:) — longest id prefix"]
    P -->|nil| U["TokenTotals.unpricedTokens"]
    P --> T{"promptTokens > longContextThreshold?"}
    T -->|yes| L["long-context rates"]
    T -->|no| N["base rates"]
    L & N --> C["PriceTable.cost(of:): input, output,<br/>cache write 5 m ×1.25 / 1 h ×2 of input,<br/>cache read, × fastMultiplier, + web search"]
    C --> B["CostBreakdown"]
    F["pricing.json"] -->|PriceTable.loadOrInstall(at:)| P
```

### Where

| Requirement | File | Symbols |
|---|---|---|
| R-CMCST-001 | `Sources/ClaudeMonCore/Pricing.swift` | PriceTable.price(for:), PriceTable.standard |
| R-CMCST-002 | `Sources/ClaudeMonCore/Pricing.swift` | PriceTable.cost(of:), ModelPrice.cacheWrite5mMultiplier, ModelPrice.cacheWrite1hMultiplier |
| R-CMCST-003 | `Sources/ClaudeMonCore/Pricing.swift` | ModelPrice.longContextThreshold, PriceTable.cost(of:) |
| R-CMCST-004 | `Sources/ClaudeMonCore/Pricing.swift` | ModelPrice.fastMultiplier |
| R-CMCST-005 | `Sources/ClaudeMonCore/Pricing.swift` | PriceTable.webSearchPerThousand |
| R-CMCST-006 | `Sources/ClaudeMonCore/Pricing.swift` | PriceTable.loadOrInstall(at:) |
| R-CMCST-006 | `Sources/ClaudeMon/AppModel.swift` | AppModel.reloadPrices(), pricesURL |
| R-CMCST-007 | `Sources/ClaudeMonCore/Reports.swift` | TokenTotals.unpricedTokens |

### Why

- **List prices as of 2026-10-06** come from the Claude API skill's reference: Opus 5.5 $4/$20 per MTok with cache reads at $0.20; Opus 5 $5/$25/$0.50; Sonnet 5 and 5.5 $2/$10/$0.20; Fable 5.1 $10/$50/$0.25; Haiku 5.5 $0.10/$0.50, rising to $0.50/$2.50 above a 100K prompt. Cache-read rates differ by model, so they are stored per model rather than as a fixed multiple of the input price.
- **A user-editable file** rather than code, because list prices change between releases.
- **Unknown models are counted as unpriced**, so a missing price is visible instead of silently lowering the total.

### How to test

```sh
xcrun swift test --filter PricingTests
```

| Case | Level | How |
|---|---|---|
| R-CMCST-001.T1 | unit | `PricingTests.datedIdsMatchByLongestPrefix` |
| R-CMCST-002.T1 | unit | `PricingTests.opus55Cost` |
| R-CMCST-003.T1 | unit | `PricingTests.haiku55LongContextTier` |
| R-CMCST-004.T1 | unit | `PricingTests.fastModeDoublesPrice` |
| R-CMCST-007.T1 | unit | `ReportTests.reportTotalsOnlyIncludeThePeriod` (`unpricedTokens == 7`) |
| R-CMCST-005, -006 | manual | Specified, not yet executed as recorded verification items |

### Limits

- The Haiku 5.5 cache-read rate ($0.01) and its long-context cache-read rate ($0.05) are derived (0.1 × input), not quoted.
- Batch, Priority Tier and regional pricing are not modelled; Claude Code uses none of them.

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): base section |

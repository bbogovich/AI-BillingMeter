import ClaudeMonCore
import Foundation

// Usage: claudemon-report [--billing-day N] [--plan-price USD] [--no-cache]
// Prints today / week / billing-month totals computed by the same code the app uses.

var billingDay = 1
var planPrice: Double?
var useCache = true
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--billing-day": billingDay = Int(args.next() ?? "") ?? 1
    case "--plan-price": planPrice = Double(args.next() ?? "")
    case "--no-cache": useCache = false
    default:
        print("usage: claudemon-report [--billing-day N] [--plan-price USD] [--no-cache]")
        exit(2)
    }
}

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ClaudeMon", isDirectory: true)
let cacheURL = useCache
    ? support.appendingPathComponent("usage-cache.json")
    : FileManager.default.temporaryDirectory.appendingPathComponent("claudemon-\(UUID().uuidString).json")
let prices = PriceTable.loadOrInstall(at: support.appendingPathComponent("pricing.json"))
// The terminal summarizes with the app's own preferences, so it can never summarize more than the
// app would. There is deliberately no flag to override the window.
// trace: R-CMCLI-004 <- F-14
let appDefaults = UserDefaults(suiteName: "com.bogovich.ClaudeMon")
let policy = HistoryPolicy(detailedMonths: appDefaults?.object(forKey: "detailedHistoryMonths") as? Int ?? 1,
                           firstWeekday: appDefaults?.string(forKey: "weekStart") == "sunday" ? 1 : 2)
let store = TranscriptStore(roots: TranscriptStore.defaultRoots(), cacheURL: cacheURL)
let now = Date()
let data = await store.refresh(now: now, policy: policy, prices: prices)
let entries = data.entries
if !useCache { try? FileManager.default.removeItem(at: cacheURL) }

let builder = ReportBuilder(prices: prices, billingDay: billingDay, weekStart: .monday)

func tok(_ n: Int) -> String { n.formatted() }
func usd(_ v: Double) -> String { String(format: "$%.2f", v) }

print("Tracked API calls: \(entries.count) detailed · \(data.summaries.map(\.requests).reduce(0, +)) in \(data.summaries.count) weekly summaries")
for p in ReportPeriod.allCases {
    let r = builder.report(p, data: data, now: now)
    let t = r.totals
    print("\n== \(p.title): \(r.interval.start.formatted()) – \(r.interval.end.formatted())")
    print("  total \(tok(t.total))  input \(tok(t.input))  output \(tok(t.output))  cache-write \(tok(t.cacheWrite))  cache-read \(tok(t.cacheRead))")
    print("  requests \(t.requests)  API cost \(usd(t.cost.total))" + (t.unpricedTokens > 0 ? "  unpriced tokens \(tok(t.unpricedTokens))" : ""))
    for m in r.byModel { print("    \(m.name): \(tok(m.totals.total)) tokens, \(usd(m.totals.cost.total))") }
}
let b = builder.billingComparison(entries: entries, summaries: data.summaries, now: now, planPrice: planPrice)
print("\nBilling: \(usd(b.apiCostToDate)) so far, projected \(usd(b.projectedApiCost))" +
      (b.planPrice.map { " vs plan \(usd($0))" } ?? ""))

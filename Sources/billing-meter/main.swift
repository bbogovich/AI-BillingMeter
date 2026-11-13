import BillingMeterCore
import Foundation

// Usage: billing-meter [--billing-day N] [--plan-price USD] [--no-cache] [--projects]
//                      [--export FILE] [--import FILE]
// Prints today / week / billing-month / all-time totals computed by the same code the app uses.
// All-time lists every project; --projects lists projects for the other periods too.
// --export writes all tracked history to FILE; --import adds the history in such a file (as the
// app's Settings > Move history to another Mac does), then prints the report.

var billingDay = 1
var planPrice: Double?
var useCache = true
var showProjects = false
var exportURL: URL?
var importURL: URL?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--billing-day": billingDay = Int(args.next() ?? "") ?? 1
    case "--plan-price": planPrice = Double(args.next() ?? "")
    case "--no-cache": useCache = false
    case "--projects": showProjects = true
    case "--export": exportURL = args.next().map { URL(fileURLWithPath: $0) }
    case "--import": importURL = args.next().map { URL(fileURLWithPath: $0) }
    default:
        print("usage: billing-meter [--billing-day N] [--plan-price USD] [--no-cache] [--projects] [--export FILE] [--import FILE]")
        exit(2)
    }
}

AppPaths.migrateLegacyData()
let cacheURL = useCache
    ? AppPaths.cacheURL
    : FileManager.default.temporaryDirectory.appendingPathComponent("billing-meter-\(UUID().uuidString).json")
let prices = PriceTable.loadOrInstall(at: AppPaths.pricesURL)
// The terminal summarizes with the app's own preferences, so it can never summarize more than the
// app would. There is deliberately no flag to override the window.
// trace: R-CMCLI-004 <- F-14
let appDefaults = AppPaths.defaults
let policy = HistoryPolicy(detailedMonths: appDefaults.object(forKey: "detailedHistoryMonths") as? Int ?? 1,
                           firstWeekday: appDefaults.string(forKey: "weekStart") == "sunday" ? 1 : 2)
let store = TranscriptStore(roots: TranscriptStore.defaultRoots(), cacheURL: cacheURL)
let now = Date()
var data = await store.refresh(now: now, policy: policy, prices: prices)
if let importURL {
    do {
        let archive = try HistoryArchive.decode(Data(contentsOf: importURL))
        let (result, imported) = await store.importArchive(archive, now: now, policy: policy, prices: prices)
        data = imported
        print(result.summary)
    } catch {
        print("Import failed: \(error.localizedDescription)")
        exit(1)
    }
}
if let exportURL {
    do {
        let archive = await store.exportArchive(now: now)
        try archive.encoded().write(to: exportURL, options: .atomic)
        print("Exported \(archive.sources.map(\.requests).reduce(0, +)) calls to \(exportURL.path)")
    } catch {
        print("Export failed: \(error.localizedDescription)")
        exit(1)
    }
}
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
    if p == .all || showProjects {
        // trace: F-16 — every project's total, with the directory its sessions started in.
        print("  by project:")
        for row in r.byProject {
            print("    \(row.name): \(usd(row.totals.cost.total)), \(tok(row.totals.total)) tokens" +
                  (row.detail.map { "  (\($0))" } ?? ""))
        }
    }
}
let b = builder.billingComparison(entries: entries, summaries: data.summaries, now: now, planPrice: planPrice)
print("\nBilling: \(usd(b.apiCostToDate)) so far, projected \(usd(b.projectedApiCost))" +
      (b.planPrice.map { " vs plan \(usd($0))" } ?? ""))

import Foundation

public enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, billing
    /// Everything recorded, by calendar month (F-15).
    case all
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .billing: "Billing month"
        case .all: "All"
        }
    }
}

/// How the "current week" is bounded.
public enum WeekStart: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follow the plan's weekly-limit window (falls back to Monday when unknown).
    case planReset
    case monday
    case sunday
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .planReset: "Plan's weekly reset"
        case .monday: "Monday"
        case .sunday: "Sunday"
        }
    }
}

public struct TokenTotals: Hashable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheWrite = 0
    public var cacheRead = 0
    public var requests = 0
    public var cost = CostBreakdown()
    /// Tokens from models missing from the price table (not included in `cost`).
    public var unpricedTokens = 0

    public init() {}

    public var total: Int { input + output + cacheWrite + cacheRead }

    mutating func add(_ e: UsageEntry, cost c: CostBreakdown?) {
        input += e.inputTokens
        output += e.outputTokens
        cacheWrite += e.cacheWriteTokens
        cacheRead += e.cacheReadTokens
        requests += 1
        if let c { cost = cost + c } else { unpricedTokens += e.totalTokens }
    }

    mutating func add(_ s: WeeklySummary, cost c: CostBreakdown?) {
        input += s.inputTokens
        output += s.outputTokens
        cacheWrite += s.cacheWriteTokens
        cacheRead += s.cacheReadTokens
        requests += s.requests
        if let c { cost = cost + c } else { unpricedTokens += s.totalTokens }
    }
}

/// One stacked bar segment: usage of one model family within one time bucket.
public struct UsageBucket: Identifiable, Hashable, Sendable {
    public var start: Date
    public var family: String
    public var tokens: Int
    public var cost: Double
    public var id: String { "\(start.timeIntervalSince1970)-\(family)" }
}

public struct BreakdownRow: Identifiable, Hashable, Sendable {
    public var name: String
    public var totals: TokenTotals
    /// For a project, the directory its sessions were started in, when known.
    public var detail: String? = nil
    public var id: String { name }
}

public struct PeriodReport: Sendable {
    public var period: ReportPeriod
    public var interval: DateInterval
    /// `interval` widened to whole buckets, for the chart's x-axis. A plan week that
    /// resets mid-evening spans parts of eight calendar days.
    public var chartDomain: ClosedRange<Date>
    public var bucketUnit: Calendar.Component
    public var totals: TokenTotals
    public var buckets: [UsageBucket]
    public var byModel: [BreakdownRow]
    public var byProject: [BreakdownRow]
    /// Set when the period starts before the detail window, so part of it is weekly summaries.
    public var summarizedBefore: Date? = nil
}

/// API-metered cost for the billing period compared with the flat plan price.
public struct BillingComparison: Sendable {
    public var interval: DateInterval
    public var elapsedFraction: Double
    public var apiCostToDate: Double
    public var projectedApiCost: Double
    public var planPrice: Double?

    /// Positive when the plan is cheaper than metered API billing would have been.
    public var projectedSavings: Double? { planPrice.map { projectedApiCost - $0 } }
    /// Metered value delivered per plan dollar, to date.
    public var valueMultipleToDate: Double? {
        guard let p = planPrice, p > 0 else { return nil }
        return apiCostToDate / p
    }
}

public struct ReportBuilder: Sendable {
    public var prices: PriceTable
    public var calendar: Calendar
    public var billingDay: Int
    public var weekStart: WeekStart
    /// Start of the plan's weekly window, when known from claude.ai.
    public var planWeekStart: Date?
    /// Directory of each Claude Code project folder, for project names (`UsageData.projectPaths`).
    public var projectPaths: [String: String] = [:]

    public init(prices: PriceTable, calendar: Calendar = .current, billingDay: Int = 1,
                weekStart: WeekStart = .planReset, planWeekStart: Date? = nil) {
        self.prices = prices
        self.calendar = calendar
        self.billingDay = min(max(billingDay, 1), 28)
        self.weekStart = weekStart
        self.planWeekStart = planWeekStart
    }

    // MARK: Intervals

    public func interval(for period: ReportPeriod, now: Date) -> DateInterval {
        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now)!
        case .week:
            return weekInterval(now: now)
        case .billing:
            return billingInterval(now: now)
        case .all:
            return calendar.dateInterval(of: .month, for: now)!
        }
    }

    /// From the first month with any usage to the end of the current month.
    func allInterval(entries: [UsageEntry], summaries: [WeeklySummary], now: Date) -> DateInterval {
        let current = calendar.dateInterval(of: .month, for: now)!
        let earliest = [entries.lazy.map(\.timestamp).min(), summaries.lazy.map(\.weekStart).min()]
            .compactMap { $0 }.min()
        guard let earliest, earliest < current.start else { return current }
        return DateInterval(start: calendar.dateInterval(of: .month, for: earliest)!.start, end: current.end)
    }

    func weekInterval(now: Date) -> DateInterval {
        if weekStart == .planReset, let s = planWeekStart, s <= now, now.timeIntervalSince(s) < 7 * 86_400 {
            return DateInterval(start: s, duration: 7 * 86_400)
        }
        var cal = calendar
        cal.firstWeekday = weekStart == .sunday ? 1 : 2
        return cal.dateInterval(of: .weekOfYear, for: now)!
    }

    public func billingInterval(now: Date) -> DateInterval {
        var comps = calendar.dateComponents([.year, .month], from: now)
        comps.day = billingDay
        var start = calendar.date(from: comps)!
        if start > now { start = calendar.date(byAdding: .month, value: -1, to: start)! }
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    // MARK: Reports

    /// Report over detailed calls and weekly summaries. A summary counts toward a period when its
    /// week segment starts inside it, and is charted at that start.
    /// trace: R-CMRPT-012, R-CMRPT-013 <- F-14
    public func report(_ period: ReportPeriod, data: UsageData, now: Date) -> PeriodReport {
        var builder = self
        builder.projectPaths.merge(data.projectPaths) { mine, _ in mine }
        return builder.report(period, entries: data.entries, summaries: data.summaries,
                              summarizedBefore: data.summarizedBefore, now: now)
    }

    public func report(_ period: ReportPeriod, entries: [UsageEntry], summaries: [WeeklySummary] = [],
                       summarizedBefore: Date? = nil, now: Date) -> PeriodReport {
        let interval = period == .all
            ? allInterval(entries: entries, summaries: summaries, now: now)
            : interval(for: period, now: now)
        let unit: Calendar.Component = switch period {
        case .today: .hour
        case .all: .month
        case .week, .billing: .day
        }
        var totals = TokenTotals()
        var models: [String: TokenTotals] = [:]
        var projects: [String: TokenTotals] = [:]
        var projectNames: [String: String] = [:]
        var bucketMap: [Date: [String: (Int, Double)]] = [:]

        for e in entries where e.timestamp >= interval.start && e.timestamp < interval.end {
            let c = prices.cost(of: e)
            totals.add(e, cost: c)
            models[e.model, default: TokenTotals()].add(e, cost: c)
            let pk = ProjectDirectory.key(projectID: e.projectID, project: e.project)
            projects[pk, default: TokenTotals()].add(e, cost: c)
            projectNames[pk] = projectNames[pk] ?? e.project
            let b = calendar.dateInterval(of: unit, for: e.timestamp)!.start
            let fam = Self.family(of: e.model)
            let prev = bucketMap[b, default: [:]][fam] ?? (0, 0)
            bucketMap[b, default: [:]][fam] = (prev.0 + e.totalTokens, prev.1 + (c?.total ?? 0))
        }
        for s in summaries where s.weekStart >= interval.start && s.weekStart < interval.end {
            let c = prices.cost(of: s)
            totals.add(s, cost: c)
            models[s.model, default: TokenTotals()].add(s, cost: c)
            let pk = ProjectDirectory.key(projectID: s.projectID, project: s.project)
            projects[pk, default: TokenTotals()].add(s, cost: c)
            projectNames[pk] = projectNames[pk] ?? s.project
            let b = calendar.dateInterval(of: unit, for: s.weekStart)!.start
            let fam = Self.family(of: s.model)
            let prev = bucketMap[b, default: [:]][fam] ?? (0, 0)
            bucketMap[b, default: [:]][fam] = (prev.0 + s.totalTokens, prev.1 + (c?.total ?? 0))
        }

        let buckets = bucketMap.flatMap { start, fams in
            fams.map { UsageBucket(start: start, family: $0.key, tokens: $0.value.0, cost: $0.value.1) }
        }.sorted { ($0.start, $0.family) < ($1.start, $1.family) }

        func rows(_ d: [String: TokenTotals], names: [String: String] = [:],
                  details: [String: String] = [:]) -> [BreakdownRow] {
            d.map { BreakdownRow(name: names[$0.key] ?? $0.key, totals: $0.value, detail: details[$0.key]) }
                .sorted { ($0.totals.cost.total, $0.totals.total, $1.name) > ($1.totals.cost.total, $1.totals.total, $0.name) }
        }
        // trace: F-16 — one row per project folder, named uniquely.
        let names = ProjectDirectory.displayNames(keys: Set(projects.keys), paths: projectPaths,
                                                  fallbackNames: projectNames.mapValues { $0.isEmpty ? "(unknown)" : $0 })
        let domainStart = calendar.dateInterval(of: unit, for: interval.start)!.start
        let lastInstant = interval.end.addingTimeInterval(-1)
        let domainEnd = calendar.dateInterval(of: unit, for: lastInstant)!.end
        return PeriodReport(period: period, interval: interval, chartDomain: domainStart...domainEnd, bucketUnit: unit, totals: totals,
                            buckets: buckets, byModel: rows(models),
                            byProject: rows(projects, names: names, details: projectPaths),
                            summarizedBefore: summarizedBefore.flatMap { interval.start < $0 ? $0 : nil })
    }

    public func billingComparison(entries: [UsageEntry], summaries: [WeeklySummary] = [], now: Date,
                                  planPrice: Double?) -> BillingComparison {
        let interval = billingInterval(now: now)
        let cost = entries.lazy
            .filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
            .compactMap { prices.cost(of: $0)?.total }
            .reduce(0, +)
            + summaries.lazy
            .filter { $0.weekStart >= interval.start && $0.weekStart < interval.end }
            .compactMap { prices.cost(of: $0)?.total }
            .reduce(0, +)
        let elapsed = min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
        // Avoid wild projections in the first hours of a period.
        let projected = elapsed > 1.0 / 30 ? cost / elapsed : cost
        return BillingComparison(interval: interval, elapsedFraction: elapsed, apiCostToDate: cost,
                                 projectedApiCost: max(projected, cost), planPrice: planPrice)
    }

    public static func family(of model: String) -> String {
        for f in ["fable", "mythos", "opus", "sonnet", "haiku"] where model.contains(f) {
            return f.capitalized
        }
        return "Other"
    }
}

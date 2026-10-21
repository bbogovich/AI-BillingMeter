import Foundation

/// How much history is kept in full detail (F-14).
/// trace: R-CMUSE-011 <- F-14
public struct HistoryPolicy: Hashable, Sendable {
    /// Months before the current calendar month that keep per-call detail (0–24).
    public var detailedMonths: Int
    /// Calendar weekday that starts a week segment: 2 = Monday (default), 1 = Sunday.
    public var firstWeekday: Int

    public static let range = 0...24

    public init(detailedMonths: Int = 1, firstWeekday: Int = 2) {
        self.detailedMonths = min(max(detailedMonths, Self.range.lowerBound), Self.range.upperBound)
        self.firstWeekday = firstWeekday == 1 ? 1 : 2
    }

    public static let `default` = HistoryPolicy()
}

/// Token totals for the calls of one week segment that share a model, project and pricing rate.
/// trace: R-CMUSE-012 <- F-14
public struct WeeklySummary: Codable, Hashable, Sendable {
    public var weekStart: Date
    public var model: String
    public var project: String
    public var fast: Bool
    public var longContext: Bool
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    public var webSearches: Int

    public init(weekStart: Date, model: String, project: String, fast: Bool, longContext: Bool) {
        self.weekStart = weekStart
        self.model = model
        self.project = project
        self.fast = fast
        self.longContext = longContext
        requests = 0; inputTokens = 0; outputTokens = 0; cacheWrite5mTokens = 0
        cacheWrite1hTokens = 0; cacheReadTokens = 0; webSearches = 0
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    struct Key: Hashable {
        var weekStart: Date, model: String, project: String, fast: Bool, longContext: Bool
    }

    var key: Key { Key(weekStart: weekStart, model: model, project: project, fast: fast, longContext: longContext) }

    mutating func add(_ e: UsageEntry) {
        requests += 1
        inputTokens += e.inputTokens
        outputTokens += e.outputTokens
        cacheWrite5mTokens += e.cacheWrite5mTokens
        cacheWrite1hTokens += e.cacheWrite1hTokens
        cacheReadTokens += e.cacheReadTokens
        webSearches += e.webSearches
    }

    mutating func add(_ s: WeeklySummary) {
        requests += s.requests
        inputTokens += s.inputTokens
        outputTokens += s.outputTokens
        cacheWrite5mTokens += s.cacheWrite5mTokens
        cacheWrite1hTokens += s.cacheWrite1hTokens
        cacheReadTokens += s.cacheReadTokens
        webSearches += s.webSearches
    }
}

/// Everything the store knows: detailed calls inside the detail window, weekly summaries before it.
public struct UsageData: Sendable {
    public var entries: [UsageEntry]
    public var summaries: [WeeklySummary]
    /// Start of the detail window at the latest summarizing; transcript lines before it are ignored.
    public var summarizedBefore: Date?

    public init(entries: [UsageEntry], summaries: [WeeklySummary] = [], summarizedBefore: Date? = nil) {
        self.entries = entries
        self.summaries = summaries
        self.summarizedBefore = summarizedBefore
    }
}

public enum HistoryCompactor {
    /// First day of the calendar month `policy.detailedMonths` months before `now`'s month.
    /// trace: R-CMUSE-011 <- F-14
    public static func windowStart(now: Date, policy: HistoryPolicy, calendar: Calendar) -> Date {
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        return calendar.date(byAdding: .month, value: -policy.detailedMonths, to: monthStart)!
    }

    /// The later of the date's calendar-week start and its month's first day, so a segment never
    /// spans two months.
    /// trace: R-CMUSE-013 <- F-14
    public static func segmentStart(of date: Date, policy: HistoryPolicy, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = policy.firstWeekday
        let week = cal.dateInterval(of: .weekOfYear, for: date)!.start
        let month = cal.dateInterval(of: .month, for: date)!.start
        return max(week, month)
    }

    /// Moves every call timed before `before` into the weekly summaries, adding to existing ones.
    /// trace: R-CMUSE-012 <- F-14
    public static func compact(entries: [UsageEntry], summaries: [WeeklySummary], before: Date,
                               policy: HistoryPolicy, calendar: Calendar,
                               prices: PriceTable) -> (entries: [UsageEntry], summaries: [WeeklySummary]) {
        var byKey = Dictionary(summaries.map { ($0.key, $0) }, uniquingKeysWith: { a, b in
            var m = a; m.add(b); return m
        })
        var kept: [UsageEntry] = []
        kept.reserveCapacity(entries.count)
        for e in entries {
            guard e.timestamp < before else { kept.append(e); continue }
            var s = WeeklySummary(weekStart: segmentStart(of: e.timestamp, policy: policy, calendar: calendar),
                                  model: e.model, project: e.project, fast: e.fast,
                                  longContext: prices.usesLongContextRate(e))
            s = byKey[s.key] ?? s
            s.add(e)
            byKey[s.key] = s
        }
        let sorted = byKey.values.sorted {
            ($0.weekStart, $0.model, $0.project, $0.fast ? 1 : 0, $0.longContext ? 1 : 0)
                < ($1.weekStart, $1.model, $1.project, $1.fast ? 1 : 0, $1.longContext ? 1 : 0)
        }
        return (kept, sorted)
    }
}

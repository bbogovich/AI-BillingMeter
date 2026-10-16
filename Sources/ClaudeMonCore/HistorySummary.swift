import Foundation

/// How much history is kept in full detail (F-14). STUB — red phase.
public struct HistoryPolicy: Hashable, Sendable {
    public var detailedMonths: Int
    public var firstWeekday: Int

    public init(detailedMonths: Int = 1, firstWeekday: Int = 2) {
        self.detailedMonths = detailedMonths
        self.firstWeekday = firstWeekday
    }

    public static let `default` = HistoryPolicy()
}

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

    public var totalTokens: Int { 0 }
}

public struct UsageData: Sendable {
    public var entries: [UsageEntry]
    public var summaries: [WeeklySummary]
    public var summarizedBefore: Date?

    public init(entries: [UsageEntry], summaries: [WeeklySummary] = [], summarizedBefore: Date? = nil) {
        self.entries = entries
        self.summaries = summaries
        self.summarizedBefore = summarizedBefore
    }
}

public enum HistoryCompactor {
    public static func windowStart(now: Date, policy: HistoryPolicy, calendar: Calendar) -> Date { now }

    public static func segmentStart(of date: Date, policy: HistoryPolicy, calendar: Calendar) -> Date { date }

    public static func compact(entries: [UsageEntry], summaries: [WeeklySummary], before: Date,
                               policy: HistoryPolicy, calendar: Calendar,
                               prices: PriceTable) -> (entries: [UsageEntry], summaries: [WeeklySummary]) {
        (entries, summaries)
    }
}

public extension PriceTable {
    func cost(of summary: WeeklySummary) -> CostBreakdown? { nil }
}

public extension TranscriptStore {
    func refresh(now: Date, policy: HistoryPolicy, prices: PriceTable = .standard,
                 calendar: Calendar = .current) -> UsageData {
        UsageData(entries: refresh())
    }

    func rescanAll(now: Date, policy: HistoryPolicy, prices: PriceTable = .standard,
                   calendar: Calendar = .current) -> UsageData {
        UsageData(entries: rescanAll())
    }
}

public extension ReportBuilder {
    func report(_ period: ReportPeriod, data: UsageData, now: Date) -> PeriodReport {
        report(period, entries: data.entries, now: now)
    }
}

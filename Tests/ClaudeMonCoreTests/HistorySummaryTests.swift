import Foundation
import Testing
@testable import ClaudeMonCore

// Spec-derived tests for F-14 Bounded usage history (ClaudeMon-Definition spec 1.4.0, CMUSE.4 and
// related pages). Each test names the case it implements with `trace:`; all data is mock data.

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private var serial = 0
private func call(_ date: Date, model: String = "claude-opus-5-5", project: String = "Alpha",
                  input: Int = 10, output: Int = 100, write5m: Int = 0, write1h: Int = 1_000,
                  read: Int = 10_000, web: Int = 0, fast: Bool = false) -> UsageEntry {
    serial += 1
    return UsageEntry(key: "msg_\(serial)|req_\(serial)", timestamp: date, model: model, project: project,
                      inputTokens: input, outputTokens: output, cacheWrite5mTokens: write5m,
                      cacheWrite1hTokens: write1h, cacheReadTokens: read, webSearches: web, fast: fast)
}

private func tokens(_ d: UsageData) -> Int {
    d.entries.map(\.totalTokens).reduce(0, +) + d.summaries.map(\.totalTokens).reduce(0, +)
}

private func calls(_ d: UsageData) -> Int {
    d.entries.count + d.summaries.map(\.requests).reduce(0, +)
}

@Suite struct DetailWindowTests {
    let n1 = HistoryPolicy(detailedMonths: 1)

    // trace: R-CMUSE-011.T1
    @Test func defaultWindowKeepsCurrentAndPreviousMonth() {
        #expect(HistoryCompactor.windowStart(now: day(2026, 10, 15), policy: n1, calendar: cal) == day(2026, 9, 1, 0))
    }

    // trace: R-CMUSE-011.T2
    @Test func zeroMonthsKeepsOnlyCurrentMonth() {
        let p = HistoryPolicy(detailedMonths: 0)
        #expect(HistoryCompactor.windowStart(now: day(2026, 10, 15), policy: p, calendar: cal) == day(2026, 10, 1, 0))
    }

    // trace: R-CMUSE-011.T3
    @Test func windowCrossesYearBoundary() {
        #expect(HistoryCompactor.windowStart(now: day(2026, 1, 10), policy: n1, calendar: cal) == day(2025, 12, 1, 0))
    }
}

@Suite struct WeekSegmentTests {
    // trace: R-CMUSE-013.T1
    @Test func segmentsStartMondayAndNeverSpanTwoMonths() {
        let p = HistoryPolicy(detailedMonths: 1, firstWeekday: 2)
        #expect(HistoryCompactor.segmentStart(of: day(2026, 7, 31), policy: p, calendar: cal) == day(2026, 7, 27, 0))
        #expect(HistoryCompactor.segmentStart(of: day(2026, 8, 1), policy: p, calendar: cal) == day(2026, 8, 1, 0))
        #expect(HistoryCompactor.segmentStart(of: day(2026, 8, 3), policy: p, calendar: cal) == day(2026, 8, 3, 0))
    }

    // trace: R-CMUSE-013.T2
    @Test func sundayWeekStart() {
        let p = HistoryPolicy(detailedMonths: 1, firstWeekday: 1)
        #expect(HistoryCompactor.segmentStart(of: day(2026, 8, 4), policy: p, calendar: cal) == day(2026, 8, 2, 0))
    }
}

@Suite struct CompactionTests {
    let p = HistoryPolicy(detailedMonths: 1)
    let window = day(2026, 9, 1, 0)

    // trace: R-CMUSE-012.T1
    @Test func callsBeforeWindowBecomeWeeklySummaries() throws {
        let a = call(day(2026, 8, 3)), b = call(day(2026, 8, 4), output: 300), c = call(day(2026, 8, 12))
        let kept = call(day(2026, 9, 5))
        let r = HistoryCompactor.compact(entries: [a, b, c, kept], summaries: [], before: window,
                                         policy: p, calendar: cal, prices: .standard)
        #expect(r.entries == [kept])
        let byWeek = Dictionary(uniqueKeysWithValues: r.summaries.map { ($0.weekStart, $0) })
        let first = try #require(byWeek[day(2026, 8, 3, 0)])
        #expect(first.requests == 2)
        #expect(first.outputTokens == 400)
        #expect(first.cacheReadTokens == 20_000)
        #expect(byWeek[day(2026, 8, 10, 0)]?.requests == 1)
        #expect(r.summaries.count == 2)
    }

    // trace: R-CMUSE-012.T2
    @Test func summariesAreKeyedByModelProjectAndRate() {
        let d = day(2026, 8, 5)
        let mixed = [call(d), call(d, model: "claude-sonnet-5-5"), call(d, project: "Beta"), call(d, fast: true),
                     call(d)]
        let r = HistoryCompactor.compact(entries: mixed, summaries: [], before: window,
                                         policy: p, calendar: cal, prices: .standard)
        #expect(r.summaries.count == 4)
        #expect(r.summaries.map(\.requests).reduce(0, +) == 5)
    }

    // trace: R-CMUSE-012.T3
    @Test func twelveThousandCallsShrinkToAtMostNinetySixSummaries() {
        var entries: [UsageEntry] = []
        let models = ["claude-opus-5-5", "claude-sonnet-5-5"], projects = ["Alpha", "Beta", "Gamma"]
        let start = day(2026, 6, 1, 0)
        for i in 0..<12_000 {
            let t = start.addingTimeInterval(Double(i) * (92 * 86_400 / 12_000))  // spread over Jun–Aug
            entries.append(call(t, model: models[i % 2], project: projects[i % 3], input: i % 7, output: i % 500))
        }
        let before = UsageData(entries: entries)
        let r = HistoryCompactor.compact(entries: entries, summaries: [], before: window,
                                         policy: p, calendar: cal, prices: .standard)
        #expect(r.entries.isEmpty)
        #expect(r.summaries.count <= 96)  // 16 week segments (Jun 5, Jul 5, Aug 6) × 2 models × 3 projects
        #expect(tokens(UsageData(entries: r.entries, summaries: r.summaries)) == tokens(before))
        #expect(calls(UsageData(entries: r.entries, summaries: r.summaries)) == 12_000)
    }

    // trace: R-CMCST-012.T1
    @Test func summaryCostEqualsSumOfCallCosts() throws {
        let d = day(2026, 8, 6)
        let mix = [call(d, fast: true), call(d, output: 999, fast: true),
                   call(d, model: "claude-haiku-5-5", input: 150_000, read: 0),  // above the 100 K tier
                   call(d, model: "claude-haiku-5-5", input: 50_000, read: 0),   // below it
                   call(d, model: "claude-sonnet-5-5", web: 3)]
        let perCall = try mix.map { try #require(PriceTable.standard.cost(of: $0)).total }.reduce(0, +)
        let r = HistoryCompactor.compact(entries: mix, summaries: [], before: window,
                                         policy: p, calendar: cal, prices: .standard)
        let summarized = try r.summaries.map { try #require(PriceTable.standard.cost(of: $0)).total }.reduce(0, +)
        #expect(abs(summarized - perCall) < 1e-9)
    }

    @Test func compactingTwiceAddsToExistingSummaries() {
        let first = HistoryCompactor.compact(entries: [call(day(2026, 8, 3))], summaries: [], before: window,
                                             policy: p, calendar: cal, prices: .standard)
        let second = HistoryCompactor.compact(entries: [call(day(2026, 8, 4))], summaries: first.summaries,
                                              before: window, policy: p, calendar: cal, prices: .standard)
        #expect(second.summaries.count == 1)
        #expect(second.summaries.first?.requests == 2)
    }
}

@Suite struct ReportSummaryTests {
    // trace: R-CMRPT-012.T1
    @Test func billingMonthIncludesSummariesInsideThePeriod() {
        let b = ReportBuilder(prices: .standard, calendar: cal, billingDay: 15, weekStart: .monday)
        var inside = WeeklySummary(weekStart: day(2026, 9, 21, 0), model: "claude-opus-5-5", project: "Alpha",
                                   fast: false, longContext: false)
        inside.requests = 40
        inside.outputTokens = 1_000_000
        var outside = inside
        outside.weekStart = day(2026, 9, 7, 0)
        let data = UsageData(entries: [call(day(2026, 10, 2), output: 500)], summaries: [inside, outside],
                             summarizedBefore: day(2026, 10, 1, 0))
        let r = b.report(.billing, data: data, now: day(2026, 10, 10))
        #expect(r.totals.output == 1_000_500)
        #expect(r.totals.requests == 41)
        #expect(r.buckets.contains { $0.start == day(2026, 9, 21, 0) && $0.tokens == 1_000_000 })
        #expect(abs(r.totals.cost.output - 20.01) < 1e-9)
    }

    // trace: R-CMRPT-013.T1
    @Test func periodsReachingIntoSummariesAreFlagged() {
        let b = ReportBuilder(prices: .standard, calendar: cal, billingDay: 15, weekStart: .monday)
        let data = UsageData(entries: [], summaries: [], summarizedBefore: day(2026, 10, 1, 0))
        #expect(b.report(.billing, data: data, now: day(2026, 10, 10)).summarizedBefore == day(2026, 10, 1, 0))
        #expect(b.report(.today, data: data, now: day(2026, 10, 10)).summarizedBefore == nil)
    }
}

@Suite struct StoreSummaryTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cm-f14-\(UUID().uuidString)")
    var projects: URL { dir.appendingPathComponent("projects") }
    var cache: URL { dir.appendingPathComponent("cache.json") }

    func transcriptLine(id: String, at date: Date, output: Int = 100) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return """
        {"type":"assistant","timestamp":"\(iso)","requestId":"req_\(id)","sessionId":"s","cwd":"/tmp/Alpha","message":{"id":"msg_\(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}
        """
    }

    func writeTranscript(_ lines: [String]) throws {
        let p = projects.appendingPathComponent("p")
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: p.appendingPathComponent("s.jsonl"))
    }

    func store() -> TranscriptStore { TranscriptStore(roots: [projects], cacheURL: cache) }

    // trace: R-CMUSE-014.T1
    @Test func monthLeavesDetailAtFirstRefreshAfterRollover() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTranscript([transcriptLine(id: "a", at: day(2026, 8, 10)), transcriptLine(id: "b", at: day(2026, 9, 10))])
        let s = store(), n1 = HistoryPolicy(detailedMonths: 1)
        let sept = await s.refresh(now: day(2026, 9, 20), policy: n1, calendar: cal)
        #expect(sept.entries.count == 2 && sept.summaries.isEmpty)
        let oct = await s.refresh(now: day(2026, 10, 2), policy: n1, calendar: cal)
        #expect(oct.entries.map(\.key) == ["msg_b|req_b"])
        #expect(oct.summaries.count == 1 && oct.summaries[0].weekStart == day(2026, 8, 10, 0))
        #expect(oct.summarizedBefore == day(2026, 9, 1, 0))
    }

    // trace: R-CMUSE-014.T2
    @Test func loweringThePreferenceSummarizesAtNextRefresh() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTranscript([transcriptLine(id: "a", at: day(2026, 8, 10)), transcriptLine(id: "b", at: day(2026, 9, 10))])
        let s = store()
        _ = await s.refresh(now: day(2026, 10, 2), policy: HistoryPolicy(detailedMonths: 1), calendar: cal)
        let d = await s.refresh(now: day(2026, 10, 2), policy: HistoryPolicy(detailedMonths: 0), calendar: cal)
        #expect(d.entries.isEmpty)
        #expect(d.summaries.count == 2)
        #expect(d.summarizedBefore == day(2026, 10, 1, 0))
    }

    // trace: R-CMUSE-015.T1
    @Test func rescanAfterSummarizingDoesNotDoubleCount() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTranscript([transcriptLine(id: "a", at: day(2026, 8, 10)), transcriptLine(id: "b", at: day(2026, 9, 10))])
        let s = store(), n1 = HistoryPolicy(detailedMonths: 1)
        let before = await s.refresh(now: day(2026, 10, 2), policy: n1, calendar: cal)
        #expect(before.summaries.count == 1 && before.entries.count == 1)
        let after = await s.rescanAll(now: day(2026, 10, 2), policy: n1, calendar: cal)
        #expect(tokens(after) == tokens(before))
        #expect(calls(after) == 2)
        #expect(after.entries.count == 1 && after.summaries.map(\.requests) == [1])
    }

    // trace: R-CMUSE-016.T1
    @Test func raisingThePreferenceDoesNotRestoreDetail() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTranscript([transcriptLine(id: "a", at: day(2026, 8, 10)), transcriptLine(id: "b", at: day(2026, 9, 10))])
        let s = store()
        let low = await s.refresh(now: day(2026, 10, 2), policy: HistoryPolicy(detailedMonths: 0), calendar: cal)
        let high = await s.rescanAll(now: day(2026, 10, 2), policy: HistoryPolicy(detailedMonths: 3), calendar: cal)
        #expect(high.entries.isEmpty)
        #expect(high.summaries == low.summaries)
        #expect(high.summarizedBefore == day(2026, 10, 1, 0))
    }

    // trace: R-CMUSE-007.T2
    @Test func summariesSurviveANewStoreInstance() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeTranscript([transcriptLine(id: "a", at: day(2026, 8, 10)), transcriptLine(id: "b", at: day(2026, 9, 10))])
        let first = await store().refresh(now: day(2026, 10, 2), policy: .default, calendar: cal)
        try FileManager.default.removeItem(at: projects)  // Claude Code deleted the transcripts
        let again = await store().refresh(now: day(2026, 10, 2), policy: .default, calendar: cal)
        #expect(again.summaries == first.summaries)
        #expect(again.entries == first.entries)
        #expect(again.summarizedBefore == first.summarizedBefore)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
        #expect(json?["version"] as? Int == 2)
    }

    // trace: R-CMUSE-007.T3
    @Test func versionOneCacheMigrates() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = """
        {"version":1,"files":{},"entries":[{"key":"m|r","timestamp":1788000000,"model":"claude-opus-5-5","project":"Alpha","sessionId":"s","inputTokens":1,"outputTokens":2,"cacheWrite5mTokens":0,"cacheWrite1hTokens":0,"cacheReadTokens":3,"webSearches":0,"fast":false}]}
        """
        try Data(v1.utf8).write(to: cache)
        let d = await store().refresh(now: day(2026, 9, 2), policy: .default, calendar: cal)
        #expect(d.entries.map(\.key) == ["m|r"])
    }
}

// Edge tests (P59 Expand): boundaries, invalid input, time zones. Tagged with the requirement they protect.
@Suite struct HistoryEdgeTests {
    let p = HistoryPolicy(detailedMonths: 1)

    // edge: R-CMUSE-012
    @Test func emptyInputStaysEmpty() {
        let r = HistoryCompactor.compact(entries: [], summaries: [], before: day(2026, 9, 1, 0),
                                         policy: p, calendar: cal, prices: .standard)
        #expect(r.entries.isEmpty && r.summaries.isEmpty)
    }

    // edge: R-CMUSE-011
    @Test func callExactlyAtWindowStartStaysDetailed() {
        let atStart = call(day(2026, 9, 1, 0))
        let r = HistoryCompactor.compact(entries: [atStart], summaries: [], before: day(2026, 9, 1, 0),
                                         policy: p, calendar: cal, prices: .standard)
        #expect(r.entries == [atStart] && r.summaries.isEmpty)
    }

    // edge: R-CMUSE-011
    @Test func preferenceIsClampedToZeroThroughTwentyFour() {
        #expect(HistoryPolicy(detailedMonths: -3).detailedMonths == 0)
        #expect(HistoryPolicy(detailedMonths: 99).detailedMonths == 24)
        #expect(HistoryPolicy(detailedMonths: 1, firstWeekday: 5).firstWeekday == 2)
    }

    // edge: R-CMCST-012
    @Test func unpricedModelsStayUnpricedInSummaries() {
        let r = HistoryCompactor.compact(entries: [call(day(2026, 8, 5), model: "mystery-model")], summaries: [],
                                         before: day(2026, 9, 1, 0), policy: p, calendar: cal, prices: .standard)
        #expect(PriceTable.standard.cost(of: r.summaries[0]) == nil)
        let report = ReportBuilder(prices: .standard, calendar: cal, billingDay: 1)
            .report(.billing, data: UsageData(entries: [], summaries: r.summaries), now: day(2026, 8, 20))
        #expect(report.totals.unpricedTokens == r.summaries[0].totalTokens)
    }

    // edge: R-CMUSE-013
    @Test func segmentOnNewYearsDayStartsTheYear() {
        // 2027-01-01 is a Friday: its calendar week began in December, so the segment is clipped.
        #expect(HistoryCompactor.segmentStart(of: day(2027, 1, 1), policy: p, calendar: cal) == day(2027, 1, 1, 0))
        #expect(HistoryCompactor.segmentStart(of: day(2026, 12, 31), policy: p, calendar: cal) == day(2026, 12, 28, 0))
    }

    // edge: R-CMUSE-013
    @Test func daylightSavingChangeDoesNotSplitAWeek() {
        // US clocks fall back on 2026-11-01 (a Sunday): Nov 1 belongs to the segment that starts that day.
        let a = HistoryCompactor.segmentStart(of: day(2026, 11, 1, 1), policy: p, calendar: cal)
        let b = HistoryCompactor.segmentStart(of: day(2026, 11, 1, 23), policy: p, calendar: cal)
        #expect(a == b && a == day(2026, 11, 1, 0))
    }
}

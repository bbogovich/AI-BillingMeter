import Foundation
import Testing
@testable import BillingMeterCore

private func line(id: String = "msg_1", req: String = "req_1", model: String = "claude-opus-5-5",
                  ts: String = "2026-10-15T12:00:00.000Z", input: Int = 10, output: Int = 5,
                  write: Int = 100, write1h: Int = 100, read: Int = 1000, speed: String = "standard") -> String {
    """
    {"type":"assistant","timestamp":"\(ts)","requestId":"\(req)","sessionId":"s1","cwd":"/tmp/MyProj","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(write),"cache_read_input_tokens":\(read),"cache_creation":{"ephemeral_5m_input_tokens":\(write - write1h),"ephemeral_1h_input_tokens":\(write1h)},"speed":"\(speed)"}}}
    """
}

private func entry(_ s: String) -> UsageEntry? {
    TranscriptLine.parse(Data(s.utf8), fallbackProject: "fallback")
}

@Suite struct ParsingTests {
    @Test func parsesUsageLine() throws {
        let e = try #require(entry(line()))
        #expect(e.key == "msg_1|req_1")
        #expect(e.project == "MyProj")
        #expect(e.cacheWrite1hTokens == 100 && e.cacheWrite5mTokens == 0)
        #expect(e.totalTokens == 10 + 5 + 100 + 1000)
    }

    @Test func ignoresNonUsageAndSyntheticLines() {
        #expect(entry(#"{"type":"user","message":{"content":"hi"}}"#) == nil)
        #expect(entry(line(model: "<synthetic>")) == nil)
    }

    @Test func missingTTLBreakdownCountsAsFiveMinute() throws {
        let s = #"{"timestamp":"2026-10-15T12:00:00Z","requestId":"r","message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":50}}}"#
        let e = try #require(entry(s))
        #expect(e.cacheWrite5mTokens == 50 && e.cacheWrite1hTokens == 0)
    }

    @Test func duplicatesMergeWithMaxPerField() throws {
        // Claude Code writes the same response several times; later lines carry final output counts.
        let a = try #require(entry(line(output: 3)))
        let b = try #require(entry(line(output: 196)))
        #expect(a.merged(with: b).outputTokens == 196)
        #expect(b.merged(with: a).outputTokens == 196)
    }
}

@Suite struct PricingTests {
    let table = PriceTable.standard

    @Test func opus55Cost() throws {
        let e = UsageEntry(key: "k", timestamp: .now, model: "claude-opus-5-5",
                           inputTokens: 1_000_000, outputTokens: 1_000_000,
                           cacheWrite5mTokens: 1_000_000, cacheWrite1hTokens: 1_000_000,
                           cacheReadTokens: 1_000_000)
        let c = try #require(table.cost(of: e))
        #expect(abs(c.input - 4) < 1e-9)
        #expect(abs(c.output - 20) < 1e-9)
        #expect(abs(c.cacheWrite - (5 + 8)) < 1e-9)
        #expect(abs(c.cacheRead - 0.20) < 1e-9)
    }

    @Test func fastModeDoublesPrice() throws {
        let e = UsageEntry(key: "k", timestamp: .now, model: "claude-opus-5-5", outputTokens: 1_000_000, fast: true)
        #expect(abs(try #require(table.cost(of: e)).output - 40) < 1e-9)
    }

    @Test func datedIdsMatchByLongestPrefix() {
        #expect(table.price(for: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(table.price(for: "claude-opus-5")?.input == 5)
        #expect(table.price(for: "claude-opus-5-5")?.input == 4)
        #expect(table.price(for: "gpt-4") == nil)
    }

    @Test func haiku55LongContextTier() throws {
        let big = UsageEntry(key: "b", timestamp: .now, model: "claude-haiku-5-5", inputTokens: 100_001)
        let threshold = UsageEntry(key: "c", timestamp: .now, model: "claude-haiku-5-5", inputTokens: 100_000)
        #expect(abs(try #require(table.cost(of: big)).input - 100_001 * 0.50 / 1e6) < 1e-12)
        #expect(abs(try #require(table.cost(of: threshold)).input - 100_000 * 0.10 / 1e6) < 1e-12)
    }
}

@Suite struct ReportTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func billingIntervalBeforeAndAfterBillingDay() {
        let b = ReportBuilder(prices: .standard, calendar: cal, billingDay: 15)
        let before = b.billingInterval(now: date(2026, 10, 10))
        #expect(before.start == cal.startOfDay(for: date(2026, 9, 15)))
        #expect(before.end == cal.startOfDay(for: date(2026, 10, 15)))
        let after = b.billingInterval(now: date(2026, 10, 15, 0))
        #expect(after.start == cal.startOfDay(for: date(2026, 10, 15)))
    }

    @Test func weekFollowsPlanResetWhenKnown() {
        let reset = date(2026, 10, 13, 0)
        let b = ReportBuilder(prices: .standard, calendar: cal, weekStart: .planReset, planWeekStart: reset)
        #expect(b.interval(for: .week, now: date(2026, 10, 15)).start == reset)
        // Stale window (more than 7 days old) falls back to the calendar week.
        let stale = ReportBuilder(prices: .standard, calendar: cal, weekStart: .planReset,
                                  planWeekStart: date(2026, 9, 1))
        #expect(stale.interval(for: .week, now: date(2026, 10, 15)).start == cal.startOfDay(for: date(2026, 10, 12)))
    }

    @Test func reportTotalsOnlyIncludeThePeriod() {
        let b = ReportBuilder(prices: .standard, calendar: cal)
        let entries = [
            UsageEntry(key: "1", timestamp: date(2026, 10, 15, 9), model: "claude-opus-5-5", inputTokens: 100),
            UsageEntry(key: "2", timestamp: date(2026, 10, 15, 10), model: "claude-sonnet-5", inputTokens: 50),
            UsageEntry(key: "3", timestamp: date(2026, 10, 14, 10), model: "claude-opus-5-5", inputTokens: 999),
            UsageEntry(key: "4", timestamp: date(2026, 10, 15, 11), model: "mystery-model", inputTokens: 7),
        ]
        let r = b.report(.today, entries: entries, now: date(2026, 10, 15, 13))
        #expect(r.totals.input == 157)
        #expect(r.totals.requests == 3)
        #expect(r.totals.unpricedTokens == 7)
        #expect(Set(r.buckets.map(\.family)) == ["Opus", "Sonnet", "Other"])
    }

    @Test func billingProjectionScalesByElapsedTime() {
        let b = ReportBuilder(prices: .standard, calendar: cal, billingDay: 1)
        let e = [UsageEntry(key: "1", timestamp: date(2026, 9, 2), model: "claude-opus-5-5", outputTokens: 1_000_000)]
        let now = cal.date(byAdding: .second, value: Int(15 * 86_400), to: cal.startOfDay(for: date(2026, 9, 1)))!
        let c = b.billingComparison(entries: e, now: now, planPrice: 100)
        #expect(abs(c.apiCostToDate - 20) < 1e-9)
        #expect(abs(c.projectedApiCost - 40) < 1e-6) // 15 of 30 days elapsed
        #expect(abs((c.projectedSavings ?? 0) - (-60)) < 1e-6)
    }
}

@Suite struct PlanUsageTests {
    @Test func parsesLimitsArray() throws {
        let json = """
        {"five_hour":{"utilization":4.0,"resets_at":"2026-10-16T04:19:59.771577+00:00"},
         "limits":[
          {"kind":"session","group":"session","percent":4,"severity":"normal","resets_at":"2026-10-16T04:19:59.771577+00:00"},
          {"kind":"weekly_all","group":"weekly","percent":2,"severity":"normal","resets_at":"2026-10-20T03:59:59.771594+00:00"},
          {"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":"2026-10-20T04:00:00+00:00","scope":{"model":{"display_name":"Fable"}}}
         ]}
        """
        let s = try PlanUsageClient.parse(Data(json.utf8), plan: Plan(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"), fetchedAt: .now)
        #expect(s.limits.map(\.title) == ["Session (5 h)", "Weekly · all models", "Weekly · Fable"])
        #expect(s.limits[0].resetsAt != nil)
        #expect(s.plan.displayName == "Max 5x" && s.plan.listMonthlyPrice == 100)
        let start = try #require(s.weeklyWindowStart)
        #expect(abs(start.timeIntervalSince(s.limits[1].resetsAt!) + 7 * 86_400) < 1)
    }

    @Test func fallsBackToLegacyFields() throws {
        let json = #"{"five_hour":{"utilization":40,"resets_at":"2026-10-16T04:19:59Z"},"seven_day":{"utilization":12,"resets_at":"2026-10-20T03:59:59Z"},"seven_day_opus":null}"#
        let s = try PlanUsageClient.parse(Data(json.utf8), plan: Plan(subscriptionType: nil, rateLimitTier: nil), fetchedAt: .now)
        #expect(s.limits.count == 2)
        #expect(s.weeklyWindowStart != nil)
    }

    @Test func parsesKeychainCredentials() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1790000000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}"#
        let c = try PlanUsageClient.parseCredentials(Data(json.utf8))
        #expect(c.accessToken == "tok")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(c.plan.displayName == "Max 5x")
        #expect(throws: PlanUsageError.self) { try PlanUsageClient.parseCredentials(Data(#"{"other":{}}"#.utf8)) }
    }
}

@Suite struct StoreTests {
    @Test func incrementalScanHandlesPartialLinesAndDuplicates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cm-\(UUID().uuidString)")
        let proj = dir.appendingPathComponent("projects/p")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = proj.appendingPathComponent("s.jsonl")
        let cache = dir.appendingPathComponent("cache.json")

        let first = line(output: 3) + "\n" + line(id: "msg_2", req: "req_2")
        try Data(first.utf8).write(to: file) // second line has no newline yet
        let store = TranscriptStore(roots: [dir.appendingPathComponent("projects")], cacheURL: cache)
        var all = await store.refresh()
        #expect(all.count == 1)

        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: Data(("\n" + line(output: 196) + "\n").utf8))
        try h.close()
        all = await store.refresh()
        #expect(all.count == 2)
        #expect(all.first { $0.key == "msg_1|req_1" }?.outputTokens == 196)

        // A fresh store restores from the cache even if the transcript is deleted.
        try FileManager.default.removeItem(at: file)
        let restored = await TranscriptStore(roots: [dir.appendingPathComponent("projects")], cacheURL: cache).refresh()
        #expect(restored.count == 2)
    }
}

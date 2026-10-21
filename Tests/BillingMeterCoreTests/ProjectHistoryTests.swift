import Foundation
import Testing
@testable import BillingMeterCore

// Tests for F-15 (All tab, by month) and F-16 (permanent per-project totals). Mock data only.
// These features are implemented ahead of their specification; the cases below are the
// acceptance criteria the change request will need to state.

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

/// A temporary `projects` root with Claude Code-style project folders.
private struct Fixture {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bm-proj-\(UUID().uuidString)")
    var projects: URL { dir.appendingPathComponent("projects") }
    var cache: URL { dir.appendingPathComponent("usage-cache.json") }

    func store() -> TranscriptStore { TranscriptStore(roots: [projects], cacheURL: cache) }

    func line(_ id: String, at date: Date, cwd: String, output: Int = 100) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return """
        {"type":"assistant","timestamp":"\(iso)","requestId":"req_\(id)","sessionId":"s","cwd":"\(cwd)","message":{"id":"msg_\(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}
        """
    }

    /// Writes a transcript into the folder Claude Code would use for a session started in `root`.
    func write(root: String, file: String = "s.jsonl", _ lines: [String]) throws {
        let folder = projects.appendingPathComponent(ProjectDirectory.folderName(for: root))
        let url = folder.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
}

private let builder = ReportBuilder(prices: .standard, calendar: cal, weekStart: .monday)

@Suite struct ProjectIdentityTests {
    @Test func folderNameMatchesClaudeCode() {
        #expect(ProjectDirectory.folderName(for: "/Users/b/Local Documents/Projects/ClaudeMon")
                == "-Users-b-Local-Documents-Projects-ClaudeMon")
        #expect(ProjectDirectory.folderName(for: "/private/tmp/claude-501/-Users-b") == "-private-tmp-claude-501--Users-b")
    }

    @Test func sharedNamesAreToldApart() {
        let paths = ["a": "/p/LodeRunner/Docs", "b": "/p/SKTiled/Docs", "c": "/p/Solo"]
        let names = ProjectDirectory.displayNames(keys: ["a", "b", "c", "name:Docs"], paths: paths,
                                                  fallbackNames: ["name:Docs": "Docs"])
        #expect(names["a"] == "LodeRunner/Docs")
        #expect(names["b"] == "SKTiled/Docs")
        #expect(names["c"] == "Solo")
        #expect(names["name:Docs"] == "Docs")
        // History recorded before folders, sharing a folder's whole name, is labelled as such.
        let clash = ProjectDirectory.displayNames(keys: ["c", "name:Solo"], paths: paths,
                                                  fallbackNames: ["name:Solo": "Solo"])
        #expect(clash["c"] == "Solo" && clash["name:Solo"] == "Solo (folder unknown)")
    }

    @Test func projectsAreKeyedByTheFolderTheSessionStartedIn() async throws {
        let f = Fixture(); defer { f.cleanUp() }
        // Two unrelated repositories whose directories are both called Docs.
        try f.write(root: "/p/LodeRunner/Docs", [f.line("a", at: day(2026, 10, 5), cwd: "/p/LodeRunner/Docs")])
        try f.write(root: "/p/SKTiled/Docs", [f.line("b", at: day(2026, 10, 5), cwd: "/p/SKTiled/Docs")])
        // A session that cd's into a subdirectory, and a subagent transcript, stay in their project.
        try f.write(root: "/p/App", [f.line("c", at: day(2026, 10, 5), cwd: "/p/App"),
                                     f.line("d", at: day(2026, 10, 6), cwd: "/p/App/Sources")])
        try f.write(root: "/p/App", file: "s/subagents/agent-1.jsonl",
                    [f.line("e", at: day(2026, 10, 6), cwd: "/p/App/Sources")])
        let data = await f.store().refresh(now: day(2026, 10, 20), policy: .default, calendar: cal)
        let rows = builder.report(.all, data: data, now: day(2026, 10, 20)).byProject
        #expect(Set(rows.map(\.name)) == ["LodeRunner/Docs", "SKTiled/Docs", "App"])
        #expect(rows.first { $0.name == "App" }?.totals.requests == 3)
        #expect(rows.first { $0.name == "App" }?.detail == "/p/App")
    }
}

@Suite struct PermanentProjectTotalsTests {
    @Test func projectTotalsSurviveSummarizingAndDeletedTranscripts() async throws {
        let f = Fixture(); defer { f.cleanUp() }
        try f.write(root: "/p/App", [f.line("a", at: day(2026, 3, 10), cwd: "/p/App"),
                                     f.line("b", at: day(2026, 10, 10), cwd: "/p/App")])
        try f.write(root: "/p/Tool", [f.line("c", at: day(2026, 5, 10), cwd: "/p/Tool", output: 500)])
        let now = day(2026, 10, 20)
        let first = await f.store().refresh(now: now, policy: HistoryPolicy(detailedMonths: 0), calendar: cal)
        #expect(first.summaries.allSatisfy { $0.projectID != nil })
        let before = builder.report(.all, data: first, now: now).byProject

        try FileManager.default.removeItem(at: f.projects) // Claude Code deleted the transcripts
        let later = await f.store().refresh(now: day(2027, 2, 1), policy: HistoryPolicy(detailedMonths: 0), calendar: cal)
        let after = builder.report(.all, data: later, now: day(2027, 2, 1)).byProject
        #expect(after == before)
        #expect(after.map(\.name).sorted() == ["App", "Tool"])
        #expect(after.first { $0.name == "Tool" }?.detail == "/p/Tool")
    }

    @Test func olderCacheGainsProjectFoldersOnce() async throws {
        let f = Fixture(); defer { f.cleanUp() }
        try f.write(root: "/p/App", [f.line("a", at: day(2026, 10, 10), cwd: "/p/App")])
        let transcript = f.projects.appendingPathComponent(ProjectDirectory.folderName(for: "/p/App"))
            .appendingPathComponent("s.jsonl")
        let size = try FileManager.default.attributesOfItem(atPath: transcript.path)[.size] as! NSNumber
        let inode = try FileManager.default.attributesOfItem(atPath: transcript.path)[.systemFileNumber] as! NSNumber
        // A version 2 cache that has already read the whole transcript, from before folders were kept.
        let old = UsageEntry(key: "msg_a|req_a", timestamp: day(2026, 10, 10), model: "claude-opus-5-5",
                             project: "App", inputTokens: 10, outputTokens: 100, cacheReadTokens: 1000)
        let entry = try JSONSerialization.jsonObject(with: JSONEncoder.cache.encode(old))
        let cache: [String: Any] = ["version": 2, "entries": [entry], "summaries": [],
                                    "files": [transcript.path: ["offset": size, "inode": inode]]]
        try FileManager.default.createDirectory(at: f.dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: cache).write(to: f.cache)

        let data = await f.store().refresh(now: day(2026, 10, 20), policy: .default, calendar: cal)
        #expect(data.entries.count == 1)
        #expect(data.entries.first?.projectID == ProjectDirectory.folderName(for: "/p/App"))
        #expect(data.projectPaths[ProjectDirectory.folderName(for: "/p/App")] == "/p/App")
    }

    @Test func unreadableCacheIsSetAsideNotOverwritten() async throws {
        let f = Fixture(); defer { f.cleanUp() }
        try FileManager.default.createDirectory(at: f.dir, withIntermediateDirectories: true)
        let garbage = Data(#"{"version": 99, "entries": "from a newer build"}"#.utf8)
        try garbage.write(to: f.cache)
        try f.write(root: "/p/App", [f.line("a", at: day(2026, 10, 10), cwd: "/p/App")])
        _ = await f.store().refresh(now: day(2026, 10, 20), policy: .default, calendar: cal)
        let aside = try FileManager.default.contentsOfDirectory(atPath: f.dir.path)
            .filter { $0.hasPrefix("usage-cache.unreadable-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: f.dir.appendingPathComponent(aside[0])) == garbage)
    }
}

@Suite struct AllPeriodTests {
    private func entry(_ id: String, _ date: Date) -> UsageEntry {
        UsageEntry(key: id, timestamp: date, model: "claude-sonnet-5-5", project: "App",
                   inputTokens: 100, outputTokens: 100)
    }

    @Test func coversEveryMonthFromTheFirstUsage() {
        let now = day(2026, 10, 20)
        var summary = WeeklySummary(weekStart: day(2024, 3, 4, 0), model: "claude-opus-5-5", project: "Old",
                                    fast: false, longContext: false)
        summary.requests = 4; summary.inputTokens = 1_000
        let r = builder.report(.all, entries: [entry("a", day(2026, 10, 2)), entry("b", day(2025, 6, 9))],
                               summaries: [summary], now: now)
        #expect(r.bucketUnit == .month)
        #expect(r.interval.start == day(2024, 3, 1, 0))
        #expect(r.interval.end == day(2026, 11, 1, 0))
        #expect(r.totals.requests == 6)
        #expect(Set(r.buckets.map(\.start)) == [day(2024, 3, 1, 0), day(2025, 6, 1, 0), day(2026, 10, 1, 0)])
        // 32 months: more than the twelve the panel shows at once, so the chart scrolls.
        #expect(cal.dateComponents([.month], from: r.chartDomain.lowerBound, to: r.chartDomain.upperBound).month == 32)
    }

    @Test func emptyHistoryIsTheCurrentMonth() {
        let r = builder.report(.all, entries: [], now: day(2026, 10, 20))
        #expect(r.interval == cal.dateInterval(of: .month, for: day(2026, 10, 20)))
        #expect(r.buckets.isEmpty)
    }
}

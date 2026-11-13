import Foundation
import Testing
@testable import BillingMeterCore

// History export and import between Macs. All data is mock data.

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func calls(_ d: UsageData) -> Int {
    d.entries.count + d.summaries.map(\.requests).reduce(0, +)
}

private func tokens(_ d: UsageData) -> Int {
    d.entries.map(\.totalTokens).reduce(0, +) + d.summaries.map(\.totalTokens).reduce(0, +)
}

/// One simulated Mac: its own transcript folder and cache.
private struct Mac {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bm-xfer-\(UUID().uuidString)")
    var projects: URL { dir.appendingPathComponent("projects") }
    var cache: URL { dir.appendingPathComponent("cache.json") }
    func store() -> TranscriptStore { TranscriptStore(roots: [projects], cacheURL: cache) }

    func write(_ ids: [(String, Date)], file: String = "s") throws {
        let p = projects.appendingPathComponent("-tmp-Alpha")
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        let lines = ids.map { id, date in
            """
            {"type":"assistant","timestamp":"\(ISO8601DateFormatter().string(from: date))","requestId":"req_\(id)","sessionId":"s","cwd":"/tmp/Alpha","message":{"id":"msg_\(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}
            """
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: p.appendingPathComponent("\(file).jsonl"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

@Suite struct HistoryTransferTests {
    let policy = HistoryPolicy(detailedMonths: 1)
    let now = day(2026, 11, 12)

    /// Old Mac with one summarized call (August) and one detailed call (November).
    private func oldMacArchive(at time: Date? = nil) async throws -> (Mac, HistoryArchive) {
        let old = Mac()
        try old.write([("a", day(2026, 8, 10)), ("b", day(2026, 11, 3))])
        let s = old.store()
        let d = await s.refresh(now: now, policy: policy, calendar: cal)
        #expect(d.entries.count == 1 && d.summaries.count == 1)
        return (old, await s.exportArchive(now: time ?? now, sourceName: "Old Mac"))
    }

    @Test func archiveRoundTripsThroughJSON() async throws {
        let (old, archive) = try await oldMacArchive()
        defer { old.cleanup() }
        let decoded = try HistoryArchive.decode(archive.encoded())
        #expect(decoded.history == archive.history)
        #expect(decoded.history.requests == 2)
        #expect(decoded.format == HistoryArchive.formatName)
    }

    @Test func importAddsHistoryToANewMac() async throws {
        let (old, archive) = try await oldMacArchive()
        let new = Mac()
        defer { old.cleanup(); new.cleanup() }
        try new.write([("c", day(2026, 11, 11))])
        let s = new.store()
        let (result, data) = await s.importArchive(archive, now: now, policy: policy, calendar: cal)
        #expect(result.sources.map(\.outcome) == [.added])
        #expect(calls(data) == 3)
        #expect(data.summarizedBefore == day(2026, 10, 1, 0))
        // Survives a restart, and refreshing does not count it twice.
        let again = await new.store().refresh(now: now, policy: policy, calendar: cal)
        #expect(calls(again) == 3)
        #expect(tokens(again) == tokens(data))
    }

    @Test func importingTheSameExportTwiceChangesNothing() async throws {
        let (old, archive) = try await oldMacArchive()
        let new = Mac()
        defer { old.cleanup(); new.cleanup() }
        let s = new.store()
        let (_, first) = await s.importArchive(archive, now: now, policy: policy, calendar: cal)
        let (result, second) = await s.importArchive(archive, now: now, policy: policy, calendar: cal)
        #expect(result.sources.map(\.outcome) == [.unchanged])
        #expect(!result.changed)
        #expect(calls(second) == calls(first))
    }

    @Test func newerExportFromTheSameMacReplacesTheOlderOne() async throws {
        let (old, first) = try await oldMacArchive()
        let new = Mac()
        defer { old.cleanup(); new.cleanup() }
        let s = new.store()
        _ = await s.importArchive(first, now: now, policy: policy, calendar: cal)
        // The old Mac keeps working, then exports again.
        try old.write([("d", day(2026, 11, 10))], file: "t")
        let second = await old.store().exportArchive(now: day(2026, 11, 12, 18), sourceName: "Old Mac")
        let (result, data) = await s.importArchive(second, now: now, policy: policy, calendar: cal)
        #expect(result.sources.map(\.outcome) == [.replaced])
        #expect(calls(data) == 3)  // a, b, d — the summary of a is not doubled
    }

    @Test func ownExportIsNotImportedIntoItself() async throws {
        let (old, archive) = try await oldMacArchive()
        defer { old.cleanup() }
        let (result, data) = await old.store().importArchive(archive, now: now, policy: policy, calendar: cal)
        #expect(result.sources.map(\.outcome) == [.thisMac])
        #expect(calls(data) == 2)
    }

    @Test func copiedTranscriptsAreNotCountedTwice() async throws {
        let (old, archive) = try await oldMacArchive()
        let new = Mac()
        defer { old.cleanup(); new.cleanup() }
        // The November transcript was copied to the new Mac, before and after the import.
        try new.write([("b", day(2026, 11, 3))])
        let s = new.store()
        _ = await s.refresh(now: now, policy: policy, calendar: cal)
        let (_, data) = await s.importArchive(archive, now: now, policy: policy, calendar: cal)
        #expect(calls(data) == 2)
        try new.write([("b", day(2026, 11, 3)), ("e", day(2026, 11, 11))], file: "copy")
        let rescanned = await s.rescanAll(now: now, policy: policy, calendar: cal)
        #expect(calls(rescanned) == 3)
    }

    @Test func importedHistoryTravelsOnToAThirdMac() async throws {
        let (old, archive) = try await oldMacArchive()
        let middle = Mac(), last = Mac()
        defer { old.cleanup(); middle.cleanup(); last.cleanup() }
        try middle.write([("m", day(2026, 11, 5))])
        let ms = middle.store()
        _ = await ms.importArchive(archive, now: now, policy: policy, calendar: cal)
        let chained = await ms.exportArchive(now: now, sourceName: "Middle Mac")
        #expect(chained.sources.count == 2)
        let (result, data) = await last.store().importArchive(chained, now: now, policy: policy, calendar: cal)
        #expect(result.sources.map(\.outcome) == [.added, .added])
        #expect(calls(data) == 3)
    }

    @Test func importedDetailIsSummarizedWhenItLeavesTheWindow() async throws {
        let (old, archive) = try await oldMacArchive()
        let new = Mac()
        defer { old.cleanup(); new.cleanup() }
        let s = new.store()
        _ = await s.importArchive(archive, now: now, policy: policy, calendar: cal)
        let jan = await s.refresh(now: day(2027, 1, 5), policy: policy, calendar: cal)
        #expect(jan.entries.isEmpty)
        #expect(calls(jan) == 2)
    }

    @Test func otherFilesAreRejected() throws {
        #expect(throws: HistoryArchiveError.notAnArchive) {
            try HistoryArchive.decode(Data(#"{"version":3,"files":{}}"#.utf8))
        }
        #expect(throws: HistoryArchiveError.newerVersion) {
            try HistoryArchive.decode(Data(#"{"format":"ai-billing-meter-history","version":99}"#.utf8))
        }
    }
}

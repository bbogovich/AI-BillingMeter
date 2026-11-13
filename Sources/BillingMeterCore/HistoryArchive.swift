import Foundation

/// The usage history of one Mac: what its store had tracked when it was exported.
///
/// Weekly summaries carry no per-call keys, so the same summary imported twice cannot be told
/// apart from two weeks of real usage. Imported history is therefore kept per source Mac, and
/// importing from a source again replaces what came from it before rather than adding to it.
public struct SourceHistory: Codable, Hashable, Sendable {
    /// Stable identifier of the Mac's store (created with its cache).
    public var sourceID: String
    /// The Mac's name when it exported, for display only.
    public var sourceName: String
    /// When this history was taken from its store. A newer copy of a source replaces an older one.
    public var asOf: Date
    public var entries: [UsageEntry]
    public var summaries: [WeeklySummary]
    public var summarizedBefore: Date?
    public var projectPaths: [String: String]

    public init(sourceID: String, sourceName: String, asOf: Date, entries: [UsageEntry],
                summaries: [WeeklySummary], summarizedBefore: Date?, projectPaths: [String: String]) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.asOf = asOf
        self.entries = entries
        self.summaries = summaries
        self.summarizedBefore = summarizedBefore
        self.projectPaths = projectPaths
    }

    public var requests: Int { entries.count + summaries.map(\.requests).reduce(0, +) }
    /// Earliest usage this history covers.
    public var earliest: Date? {
        (entries.map(\.timestamp) + summaries.map(\.weekStart)).min()
    }
}

/// A file that carries a Mac's usage history to another Mac: its own history plus everything it
/// had imported, so history survives a chain of moves (A → B → C).
///
/// Transcript read offsets are deliberately left out: they name files and inodes on the exporting
/// Mac and mean nothing elsewhere.
public struct HistoryArchive: Codable, Sendable {
    public static let formatName = "ai-billing-meter-history"
    public static let currentVersion = 1
    public static let fileExtension = "json"

    public var format: String
    public var version: Int
    public var exportedAt: Date
    /// The exporting Mac's own history.
    public var history: SourceHistory
    /// History the exporting Mac had imported from other Macs.
    public var imported: [SourceHistory]

    public init(history: SourceHistory, imported: [SourceHistory], exportedAt: Date) {
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.history = history
        self.imported = imported
    }

    /// Every source in the archive, the exporting Mac first.
    public var sources: [SourceHistory] { [history] + imported }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> HistoryArchive {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == formatName else { throw HistoryArchiveError.notAnArchive }
        guard let v = header.version, v <= currentVersion else { throw HistoryArchiveError.newerVersion }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(HistoryArchive.self, from: data)
    }

    /// Suggested file name, e.g. `AI Billing Meter history 2026-11-12.json`.
    public static func suggestedFileName(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "AI Billing Meter history \(f.string(from: now)).\(fileExtension)"
    }
}

public enum HistoryArchiveError: Error, LocalizedError, Equatable {
    case notAnArchive
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .notAnArchive: "The file is not an AI Billing Meter history export."
        case .newerVersion: "The file was exported by a newer version of AI Billing Meter. Update the app and import it again."
        }
    }
}

/// What an import changed.
public struct HistoryImportResult: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public var name: String
        public var requests: Int
        public var outcome: Outcome
    }
    public enum Outcome: Sendable, Equatable {
        /// History from a Mac not seen before.
        case added
        /// A newer copy of history already imported from this Mac replaced the older one.
        case replaced
        /// Already imported at this date or later; nothing changed.
        case unchanged
        /// The archive's history is this Mac's own; it is already here.
        case thisMac
    }
    public var sources: [Source]

    public var changed: Bool { sources.contains { $0.outcome == .added || $0.outcome == .replaced } }

    public var summary: String {
        sources.map { s in
            let calls = "\(s.requests.formatted()) calls"
            switch s.outcome {
            case .added: return "Imported \(calls) from \(s.name)."
            case .replaced: return "Updated history from \(s.name) (\(calls))."
            case .unchanged: return "History from \(s.name) was already imported."
            case .thisMac: return "Skipped this Mac's own history."
            }
        }.joined(separator: " ")
    }
}

public enum HostName {
    /// The Mac's user-visible name, falling back to its host name.
    public static var current: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
}

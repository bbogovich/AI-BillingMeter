import Foundation

/// One billed API call, reconstructed from Claude Code transcript lines.
///
/// Claude Code writes several transcript lines per API response (one per content
/// block) that share `message.id` + `requestId`. Later lines can carry larger
/// `output_tokens` than earlier ones, so duplicates are merged with `max` per field
/// rather than "first line wins".
public struct UsageEntry: Codable, Hashable, Sendable {
    public var key: String
    public var timestamp: Date
    public var model: String
    /// Display name: the last component of the line's working directory.
    public var project: String
    /// The Claude Code project folder the transcript is in (`~/.claude/projects/<id>`), one per
    /// directory a session was started in. Unique, unlike `project`; nil in caches written
    /// before it was recorded. See `ProjectDirectory`.
    public var projectID: String?
    public var sessionId: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    public var webSearches: Int
    public var fast: Bool

    public init(key: String, timestamp: Date, model: String, project: String = "", projectID: String? = nil,
                sessionId: String = "",
                inputTokens: Int = 0, outputTokens: Int = 0, cacheWrite5mTokens: Int = 0,
                cacheWrite1hTokens: Int = 0, cacheReadTokens: Int = 0, webSearches: Int = 0, fast: Bool = false) {
        self.key = key
        self.timestamp = timestamp
        self.model = model
        self.project = project
        self.projectID = projectID
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.webSearches = webSearches
        self.fast = fast
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
    /// Tokens in the prompt (used for tiered pricing thresholds).
    public var promptTokens: Int { inputTokens + cacheWriteTokens + cacheReadTokens }

    /// Combine two observations of the same API call.
    public func merged(with other: UsageEntry) -> UsageEntry {
        var m = self
        m.timestamp = min(timestamp, other.timestamp)
        m.inputTokens = max(inputTokens, other.inputTokens)
        m.outputTokens = max(outputTokens, other.outputTokens)
        m.cacheWrite5mTokens = max(cacheWrite5mTokens, other.cacheWrite5mTokens)
        m.cacheWrite1hTokens = max(cacheWrite1hTokens, other.cacheWrite1hTokens)
        m.cacheReadTokens = max(cacheReadTokens, other.cacheReadTokens)
        m.webSearches = max(webSearches, other.webSearches)
        m.fast = fast || other.fast
        m.projectID = projectID ?? other.projectID
        return m
    }
}

/// Decodes the subset of a transcript line that carries usage.
enum TranscriptLine {
    private struct Line: Decodable {
        var type: String?
        var timestamp: String?
        var requestId: String?
        var sessionId: String?
        var uuid: String?
        var cwd: String?
        var message: Message?
    }
    private struct Message: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?
    }
    private struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?
        var cache_creation: CacheCreation?
        var server_tool_use: ServerToolUse?
        var speed: String?
    }
    private struct CacheCreation: Decodable {
        var ephemeral_5m_input_tokens: Int?
        var ephemeral_1h_input_tokens: Int?
    }
    private struct ServerToolUse: Decodable {
        var web_search_requests: Int?
    }

    private static let decoder = JSONDecoder()
    private static let marker = Data("\"usage\"".utf8)

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? iso.date(from: s)
    }

    /// Returns nil for lines that are not billed assistant responses.
    static func parse(_ data: Data, fallbackProject: String, projectID: String? = nil) -> UsageEntry? {
        parseLine(data, fallbackProject: fallbackProject, projectID: projectID)?.entry
    }

    /// The entry and the line's working directory.
    static func parseLine(_ data: Data, fallbackProject: String,
                          projectID: String? = nil) -> (entry: UsageEntry, cwd: String?)? {
        guard data.range(of: marker) != nil,
              let line = try? decoder.decode(Line.self, from: data),
              let message = line.message, let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let ts = line.timestamp.flatMap(parseDate)
        else { return nil }

        let write = usage.cache_creation_input_tokens ?? 0
        var write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? 0
        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        if write5m + write1h != write {
            // Older transcripts lack the TTL breakdown; assume the default 5-minute TTL.
            write5m = max(0, write - write1h)
        }
        let key: String
        if let id = message.id, let req = line.requestId {
            key = id + "|" + req
        } else {
            key = message.id ?? line.requestId ?? line.uuid ?? UUID().uuidString
        }
        let project = line.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallbackProject
        let entry = UsageEntry(
            key: key, timestamp: ts, model: model, project: project, projectID: projectID,
            sessionId: line.sessionId ?? "",
            inputTokens: usage.input_tokens ?? 0, outputTokens: usage.output_tokens ?? 0,
            cacheWrite5mTokens: write5m, cacheWrite1hTokens: write1h,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            webSearches: usage.server_tool_use?.web_search_requests ?? 0,
            fast: usage.speed == "fast")
        return (entry, line.cwd)
    }
}

import Foundation

/// Incrementally scans Claude Code transcripts (`~/.claude/projects/**/*.jsonl`) and keeps
/// every billed call it has ever seen in a cache file.
///
/// The cache matters beyond speed: Claude Code deletes old transcripts (30 days by default),
/// so a billing month can only be reported in full if earlier entries were kept. Calls older
/// than the detail window are kept as weekly summaries (F-14), which bounds the cache's size.
public actor TranscriptStore {
    private struct FileState: Codable {
        var offset: UInt64
        var inode: UInt64
    }
    /// Format FMT.2. Version 2 adds `summaries` and `summarizedBefore`; version 3 adds
    /// `projectPaths` and `projectID` on entries and summaries. Versions 1 and 2 still load, and
    /// are rescanned once so calls whose transcripts still exist gain their project folder.
    /// trace: R-CMUSE-007 <- F-14, F-3.CR-1
    private struct Cache: Codable {
        var version: Int
        var files: [String: FileState]
        var entries: [UsageEntry]
        var summaries: [WeeklySummary]?
        var summarizedBefore: Date?
        var projectPaths: [String: String]?
    }
    private static let cacheVersion = 3
    private static let readableVersions: Set<Int> = [1, 2, 3]

    private let roots: [URL]
    private let cacheURL: URL
    private var files: [String: FileState] = [:]
    private var entries: [String: UsageEntry] = [:]
    private var summaries: [WeeklySummary] = []
    private var summarizedBefore: Date?
    private var projectPaths: [String: String] = [:]
    private var loaded = false
    /// Set when an older cache was loaded: the next refresh rereads every transcript.
    private var needsBackfill = false

    public init(roots: [URL], cacheURL: URL) {
        self.roots = roots
        self.cacheURL = cacheURL
    }

    /// Default transcript roots: `$CLAUDE_CONFIG_DIR` (comma-separated) or `~/.claude`
    /// and `~/.config/claude`.
    public static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        let bases = configured ?? [home.appendingPathComponent(".claude"),
                                   home.appendingPathComponent(".config/claude")]
        return bases.map { $0.appendingPathComponent("projects") }
    }

    /// Scans new transcript bytes and returns all known entries.
    public func refresh() -> [UsageEntry] {
        if !loaded { loadCache() }
        if needsBackfill {
            files.removeAll()
            needsBackfill = false
        }
        var changed = false
        for (url, projectID) in transcriptFiles() {
            if scan(url, projectID: projectID) { changed = true }
        }
        if changed { saveCache() }
        return Array(entries.values)
    }

    /// Forgets all cached offsets and re-reads every transcript still on disk.
    /// Entries whose transcripts were already deleted are kept.
    public func rescanAll() -> [UsageEntry] {
        if !loaded { loadCache() }
        files.removeAll()
        return refresh()
    }

    /// Scans new transcript bytes, then summarizes every call older than the detail window.
    /// Summarizing runs on each refresh, so a month leaves detail at the first refresh after it
    /// falls out of the window. `summarizedBefore` only moves forward, so raising the policy never
    /// recreates detail that was already summarized.
    /// trace: R-CMUSE-014, R-CMUSE-016 <- F-14
    public func refresh(now: Date, policy: HistoryPolicy, prices: PriceTable = .standard,
                        calendar: Calendar = .current) -> UsageData {
        _ = refresh()
        let window = HistoryCompactor.windowStart(now: now, policy: policy, calendar: calendar)
        let boundary = max(window, summarizedBefore ?? .distantPast)
        let stale = entries.values.contains { $0.timestamp < boundary }
        if stale || boundary != summarizedBefore {
            let result = HistoryCompactor.compact(entries: Array(entries.values), summaries: summaries,
                                                  before: boundary, policy: policy, calendar: calendar,
                                                  prices: prices)
            entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.key, $0) })
            summaries = result.summaries
            summarizedBefore = boundary
            saveCache()
        }
        return UsageData(entries: Array(entries.values), summaries: summaries, summarizedBefore: summarizedBefore,
                         projectPaths: projectPaths)
    }

    /// `rescanAll()` followed by summarizing. Lines older than `summarizedBefore` are skipped
    /// while reading, so calls already summarized are not counted twice.
    public func rescanAll(now: Date, policy: HistoryPolicy, prices: PriceTable = .standard,
                          calendar: Calendar = .current) -> UsageData {
        if !loaded { loadCache() }
        files.removeAll()
        return refresh(now: now, policy: policy, prices: prices, calendar: calendar)
    }

    /// Size of the cache file in bytes, for the Settings status line.
    public func cacheFileSize() -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Scanning

    /// Every transcript, with the project folder it is in: the first path component under the
    /// root, so subagent transcripts (`<project>/<session>/subagents/…`) count toward the project.
    private func transcriptFiles() -> [(URL, String)] {
        let fm = FileManager.default
        var result: [(URL, String)] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                        options: [.skipsHiddenFiles]) else { continue }
            let rootDepth = root.standardizedFileURL.pathComponents.count
            for case let url as URL in e where url.pathExtension == "jsonl" {
                let parts = url.standardizedFileURL.pathComponents
                guard parts.count > rootDepth + 1 else { continue }
                result.append((url, parts[rootDepth]))
            }
        }
        return result
    }

    /// Reads complete lines appended since the last scan. Returns true if anything was read.
    private func scan(_ url: URL, projectID: String) -> Bool {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return false }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0

        var start: UInt64 = 0
        if let state = files[path], state.inode == inode, state.offset <= size {
            start = state.offset
        }
        guard size > start, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: start) } catch { return false }
        guard let data = try? handle.read(upToCount: Int(size - start)), !data.isEmpty else { return false }

        // Only consume up to the last newline; a trailing partial line is read next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return false }
        let complete = data[data.startIndex...lastNewline]
        let fallbackProject = projectPaths[projectID].map { URL(fileURLWithPath: $0).lastPathComponent } ?? projectID

        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let (entry, cwd) = TranscriptLine.parseLine(Data(line), fallbackProject: fallbackProject,
                                                              projectID: projectID) else { continue }
            // trace: F-16 — the folder is named after the directory the session started in.
            if projectPaths[projectID] == nil, let cwd, ProjectDirectory.folderName(for: cwd) == projectID {
                projectPaths[projectID] = cwd
            }
            // trace: R-CMUSE-015 <- F-14 — a call before summarizedBefore is already in a summary.
            if let cutoff = summarizedBefore, entry.timestamp < cutoff { continue }
            entries[entry.key] = entries[entry.key].map { $0.merged(with: entry) } ?? entry
        }
        files[path] = FileState(offset: start + UInt64(complete.count), inode: inode)
        return true // the offset moved, so the cache needs saving even if no entry changed
    }

    // MARK: - Cache

    private func loadCache() {
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let cache = try? JSONDecoder.cache.decode(Cache.self, from: data),
              Self.readableVersions.contains(cache.version) else {
            // The cache is the only copy of usage whose transcripts Claude Code has deleted, so a
            // file this build cannot read (damaged, or written by a newer build) is set aside, not
            // overwritten. trace: F-16
            setAsideUnreadableCache()
            return
        }
        files = cache.files
        entries = Dictionary(cache.entries.map { ($0.key, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
        summaries = cache.summaries ?? []
        summarizedBefore = cache.summarizedBefore
        projectPaths = cache.projectPaths ?? [:]
        needsBackfill = cache.version < 3
    }

    private func setAsideUnreadableCache() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = cacheURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: cacheURL, to: aside)
    }

    private func saveCache() {
        let cache = Cache(version: Self.cacheVersion, files: files, entries: Array(entries.values),
                          summaries: summaries, summarizedBefore: summarizedBefore, projectPaths: projectPaths)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder.cache.encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

extension JSONDecoder {
    static let cache: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

extension JSONEncoder {
    static let cache: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

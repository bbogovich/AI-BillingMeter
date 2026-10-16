import Foundation

/// Incrementally scans Claude Code transcripts (`~/.claude/projects/**/*.jsonl`) and keeps
/// every billed call it has ever seen in a cache file.
///
/// The cache matters beyond speed: Claude Code deletes old transcripts (30 days by default),
/// so a billing month can only be reported in full if earlier entries were kept.
public actor TranscriptStore {
    private struct FileState: Codable {
        var offset: UInt64
        var inode: UInt64
    }
    private struct Cache: Codable {
        var version: Int
        var files: [String: FileState]
        var entries: [UsageEntry]
    }
    private static let cacheVersion = 1

    private let roots: [URL]
    private let cacheURL: URL
    private var files: [String: FileState] = [:]
    private var entries: [String: UsageEntry] = [:]
    private var loaded = false

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
        var changed = false
        for url in transcriptFiles() {
            if scan(url) { changed = true }
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

    // MARK: - Scanning

    private func transcriptFiles() -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                        options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension == "jsonl" {
                result.append(url)
            }
        }
        return result
    }

    /// Reads complete lines appended since the last scan. Returns true if anything was read.
    private func scan(_ url: URL) -> Bool {
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
        let fallbackProject = url.deletingLastPathComponent().lastPathComponent

        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = TranscriptLine.parse(Data(line), fallbackProject: fallbackProject) else { continue }
            entries[entry.key] = entries[entry.key].map { $0.merged(with: entry) } ?? entry
        }
        files[path] = FileState(offset: start + UInt64(complete.count), inode: inode)
        return true // the offset moved, so the cache needs saving even if no entry changed
    }

    // MARK: - Cache

    private func loadCache() {
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder.cache.decode(Cache.self, from: data),
              cache.version == Self.cacheVersion else { return }
        files = cache.files
        entries = Dictionary(cache.entries.map { ($0.key, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
    }

    private func saveCache() {
        let cache = Cache(version: Self.cacheVersion, files: files, entries: Array(entries.values))
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

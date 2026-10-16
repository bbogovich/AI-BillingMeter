import Foundation

/// API list price for one model, in USD per million tokens.
public struct ModelPrice: Codable, Hashable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    /// Cache-write rates are multiples of `input` (1.25× for 5-minute TTL, 2× for 1-hour).
    public var cacheWrite5mMultiplier: Double
    public var cacheWrite1hMultiplier: Double
    /// Tiered pricing: when a request's prompt exceeds this many tokens, `input`, `output`
    /// and `cacheRead` are replaced by the `longContext*` rates.
    public var longContextThreshold: Int?
    public var longContextInput: Double?
    public var longContextOutput: Double?
    public var longContextCacheRead: Double?
    /// Fast mode multiplies every component (Opus 5.5: $8/$40 vs $4/$20).
    public var fastMultiplier: Double

    public init(input: Double, output: Double, cacheRead: Double,
                cacheWrite5mMultiplier: Double = 1.25, cacheWrite1hMultiplier: Double = 2.0,
                longContextThreshold: Int? = nil, longContextInput: Double? = nil,
                longContextOutput: Double? = nil, longContextCacheRead: Double? = nil,
                fastMultiplier: Double = 2.0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5mMultiplier = cacheWrite5mMultiplier
        self.cacheWrite1hMultiplier = cacheWrite1hMultiplier
        self.longContextThreshold = longContextThreshold
        self.longContextInput = longContextInput
        self.longContextOutput = longContextOutput
        self.longContextCacheRead = longContextCacheRead
        self.fastMultiplier = fastMultiplier
    }
}

/// Cost of a set of usage, split by component.
public struct CostBreakdown: Hashable, Sendable {
    public var input = 0.0
    public var output = 0.0
    public var cacheWrite = 0.0
    public var cacheRead = 0.0
    public var webSearch = 0.0
    public var total: Double { input + output + cacheWrite + cacheRead + webSearch }

    public init() {}

    public static func + (a: CostBreakdown, b: CostBreakdown) -> CostBreakdown {
        var r = a
        r.input += b.input
        r.output += b.output
        r.cacheWrite += b.cacheWrite
        r.cacheRead += b.cacheRead
        r.webSearch += b.webSearch
        return r
    }
}

/// Model price list. Models are matched by longest id prefix, so dated ids such as
/// `claude-haiku-4-5-20251001` resolve to `claude-haiku-4-5`.
public struct PriceTable: Codable, Sendable {
    public var asOf: String
    public var webSearchPerThousand: Double
    public var models: [String: ModelPrice]

    public init(asOf: String, webSearchPerThousand: Double, models: [String: ModelPrice]) {
        self.asOf = asOf
        self.webSearchPerThousand = webSearchPerThousand
        self.models = models
    }

    /// Anthropic first-party list prices as of 2026-10-06.
    public static let standard = PriceTable(
        asOf: "2026-10-06",
        webSearchPerThousand: 10,
        models: [
            "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
            "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
            "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
            "claude-mythos-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
            "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
            "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
            "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
            "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
            "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
            "claude-opus-4-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
            "claude-opus-4": ModelPrice(input: 15, output: 75, cacheRead: 1.50),
            "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
            "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
            "claude-sonnet-4": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
            "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01,
                                           longContextThreshold: 100_000, longContextInput: 0.50,
                                           longContextOutput: 2.50, longContextCacheRead: 0.05),
            "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.10),
            "claude-3-5-haiku": ModelPrice(input: 0.80, output: 4, cacheRead: 0.08),
        ])

    public func price(for model: String) -> ModelPrice? {
        if let exact = models[model] { return exact }
        let match = models.keys
            .filter { model.hasPrefix($0) }
            .max { $0.count < $1.count }
        return match.flatMap { models[$0] }
    }

    /// API cost of one call; nil when the model has no known price.
    public func cost(of e: UsageEntry) -> CostBreakdown? {
        guard let p = price(for: e.model) else { return nil }
        var inRate = p.input, outRate = p.output, readRate = p.cacheRead
        if let threshold = p.longContextThreshold, e.promptTokens > threshold {
            inRate = p.longContextInput ?? inRate
            outRate = p.longContextOutput ?? outRate
            readRate = p.longContextCacheRead ?? readRate
        }
        let speed = e.fast ? p.fastMultiplier : 1
        let m = 1.0 / 1_000_000
        var c = CostBreakdown()
        c.input = Double(e.inputTokens) * inRate * m * speed
        c.output = Double(e.outputTokens) * outRate * m * speed
        c.cacheWrite = (Double(e.cacheWrite5mTokens) * p.cacheWrite5mMultiplier
                        + Double(e.cacheWrite1hTokens) * p.cacheWrite1hMultiplier) * inRate * m * speed
        c.cacheRead = Double(e.cacheReadTokens) * readRate * m * speed
        c.webSearch = Double(e.webSearches) * webSearchPerThousand / 1000
        return c
    }
}

public extension PriceTable {
    /// Loads a user-editable price file, writing the defaults first if none exists.
    static func loadOrInstall(at url: URL) -> PriceTable {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url),
           let table = try? JSONDecoder().decode(PriceTable.self, from: data) {
            return table
        }
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(standard).write(to: url, options: .atomic)
        }
        return standard
    }
}

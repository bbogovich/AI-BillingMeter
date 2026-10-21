import Foundation

/// One plan limit as reported by claude.ai (the same data `/usage` shows in Claude Code).
public struct PlanLimit: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var group: String
    public var percentUsed: Double
    public var resetsAt: Date?
    public var severity: String

    public init(id: String, title: String, group: String, percentUsed: Double, resetsAt: Date?, severity: String) {
        self.id = id
        self.title = title
        self.group = group
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.severity = severity
    }

    public var percentRemaining: Double { max(0, 100 - percentUsed) }
}

public struct PlanStatus: Hashable, Sendable {
    public var plan: Plan
    public var limits: [PlanLimit]
    public var fetchedAt: Date

    public init(plan: Plan, limits: [PlanLimit], fetchedAt: Date) {
        self.plan = plan
        self.limits = limits
        self.fetchedAt = fetchedAt
    }

    /// Start of the plan's current weekly window, derived from the weekly reset time.
    public var weeklyWindowStart: Date? {
        limits.first { $0.group == "weekly" && $0.id.hasPrefix("weekly_all") }?.resetsAt
            .map { $0.addingTimeInterval(-7 * 86_400) }
    }
}

/// The subscription, as recorded in Claude Code's stored login.
public struct Plan: Hashable, Sendable {
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(subscriptionType: String?, rateLimitTier: String?) {
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    public var displayName: String {
        let tier = rateLimitTier ?? ""
        if tier.contains("max_20x") { return "Max 20x" }
        if tier.contains("max_5x") { return "Max 5x" }
        switch subscriptionType {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case let s?: return s.capitalized
        case nil: return "Unknown plan"
        }
    }

    /// List monthly price in USD, when it can be inferred.
    public var listMonthlyPrice: Double? {
        let tier = rateLimitTier ?? ""
        if tier.contains("max_20x") { return 200 }
        if tier.contains("max_5x") { return 100 }
        switch subscriptionType {
        case "max": return 100
        case "pro": return 20
        default: return nil
        }
    }
}

public enum PlanUsageError: Error, LocalizedError, Sendable {
    case noCredentials
    case loginExpired
    case http(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .noCredentials: "No Claude Code login found in the Keychain. Run `claude` and log in."
        case .loginExpired: "Claude Code login has expired. Run `claude` once to refresh it."
        case .http(let code): "claude.ai returned HTTP \(code)."
        case .badResponse: "Unexpected response from claude.ai."
        }
    }
}

/// Fetches plan utilisation using the OAuth token Claude Code keeps in the login Keychain.
///
/// The token is only read, never refreshed: refresh tokens rotate, and refreshing here
/// would sign Claude Code itself out.
public enum PlanUsageClient {
    static let keychainService = "Claude Code-credentials"
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var plan: Plan
    }

    /// Reads the item through `/usr/bin/security`, the tool Claude Code itself uses to write it.
    ///
    /// Claude Code saves its login with `security add-generic-password -U` (deleting the item
    /// first in some paths), so the item's access list trusts `security` and nothing else. Every
    /// token refresh rewrites the item and drops any "Always Allow" granted to ClaudeMon, which
    /// is why a direct `SecItemCopyMatching` read prompted again every few hours. Reading through
    /// `security` needs no prompt and does not change the item (R-CMLIM-002).
    static func readCredentials() throws -> Credentials {
        guard let data = runSecurity(["find-generic-password", "-s", keychainService, "-w"]) else {
            throw PlanUsageError.noCredentials
        }
        return try parseCredentials(data)
    }

    static func parseCredentials(_ data: Data) throws -> Credentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw PlanUsageError.noCredentials }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(accessToken: token, expiresAt: expires,
                           plan: Plan(subscriptionType: oauth["subscriptionType"] as? String,
                                      rateLimitTier: oauth["rateLimitTier"] as? String))
    }

    /// Runs `/usr/bin/security` and returns its standard output, or nil if it fails or takes
    /// longer than 10 s (it would only wait that long on a Keychain dialog).
    private static func runSecurity(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        // `-w` prints the secret followed by a newline.
        return data.last == UInt8(ascii: "\n") ? data.dropLast() : data
    }

    public static func fetch() async throws -> PlanStatus {
        let creds = try readCredentials()
        if let exp = creds.expiresAt, exp < Date() { throw PlanUsageError.loginExpired }

        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PlanUsageError.badResponse }
        if http.statusCode == 401 { throw PlanUsageError.loginExpired }
        guard http.statusCode == 200 else { throw PlanUsageError.http(http.statusCode) }
        return try parse(data, plan: creds.plan, fetchedAt: Date())
    }

    /// Parses the usage payload. Prefers the generic `limits` array; falls back to the
    /// older `five_hour` / `seven_day*` objects.
    public static func parse(_ data: Data, plan: Plan, fetchedAt: Date) throws -> PlanStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlanUsageError.badResponse
        }
        var limits: [PlanLimit] = []
        if let array = root["limits"] as? [[String: Any]] {
            for (i, l) in array.enumerated() {
                guard let kind = l["kind"] as? String,
                      let percent = (l["percent"] as? NSNumber)?.doubleValue else { continue }
                let scopeName = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                limits.append(PlanLimit(
                    id: "\(kind)#\(i)",
                    title: title(kind: kind, scope: scopeName),
                    group: l["group"] as? String ?? (kind == "session" ? "session" : "weekly"),
                    percentUsed: percent,
                    resetsAt: (l["resets_at"] as? String).flatMap(TranscriptLine.parseDate),
                    severity: l["severity"] as? String ?? "normal"))
            }
        }
        if limits.isEmpty {
            let legacy: [(String, String, String)] = [
                ("five_hour", "session", "Session (5 h)"),
                ("seven_day", "weekly", "Weekly · all models"),
                ("seven_day_opus", "weekly", "Weekly · Opus"),
                ("seven_day_sonnet", "weekly", "Weekly · Sonnet"),
            ]
            for (key, group, name) in legacy {
                guard let o = root[key] as? [String: Any],
                      let u = (o["utilization"] as? NSNumber)?.doubleValue else { continue }
                let id = key == "seven_day" ? "weekly_all#legacy" : key
                limits.append(PlanLimit(id: id, title: name, group: group, percentUsed: u,
                                        resetsAt: (o["resets_at"] as? String).flatMap(TranscriptLine.parseDate),
                                        severity: "normal"))
            }
        }
        return PlanStatus(plan: plan, limits: limits, fetchedAt: fetchedAt)
    }

    static func title(kind: String, scope: String?) -> String {
        switch kind {
        case "session": "Session (5 h)"
        case "weekly_all": "Weekly · all models"
        case "weekly_scoped": "Weekly · \(scope ?? "scoped")"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Reads only the plan from the stored login, without a network call.
    public static func storedPlan() -> Plan? {
        try? readCredentials().plan
    }
}

import ClaudeMonCore
import Foundation
import Observation
import ServiceManagement

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case limits, tokensToday, costToday, iconOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .limits: "Plan limits used (session · week)"
        case .tokensToday: "Tokens today"
        case .costToday: "API-equivalent cost today"
        case .iconOnly: "Icon only"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var entries: [UsageEntry] = []
    private(set) var planStatus: PlanStatus?
    private(set) var planError: String?
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var prices: PriceTable
    /// Bumped once a minute so time-relative views ("resets in…", today's bounds) update.
    private(set) var now = Date()

    // Settings, persisted in UserDefaults.
    var billingDay: Int { didSet { save(billingDay, "billingDay") } }
    var weekStart: WeekStart { didSet { save(weekStart.rawValue, "weekStart") } }
    /// 0 means "use the list price of the detected plan".
    var planPriceOverride: Double { didSet { save(planPriceOverride, "planPriceOverride") } }
    var fetchPlanLimits: Bool {
        didSet {
            save(fetchPlanLimits, "fetchPlanLimits")
            if fetchPlanLimits { Task { await refreshPlan() } } else { planStatus = nil; planError = nil }
        }
    }
    var planRefreshMinutes: Int { didSet { save(planRefreshMinutes, "planRefreshMinutes") } }
    var menuBarStyle: MenuBarStyle { didSet { save(menuBarStyle.rawValue, "menuBarStyle") } }

    let supportDirectory: URL
    var pricesURL: URL { supportDirectory.appendingPathComponent("pricing.json") }
    private let store: TranscriptStore
    private var loops: [Task<Void, Never>] = []
    private var lastPlanFetch: Date?
    private let snapshot: Bool

    /// `snapshot` mode (see `Snapshot.swift`) skips the background loops and the Keychain.
    init(snapshot: Bool = false) {
        self.snapshot = snapshot
        let d = UserDefaults.standard
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMon", isDirectory: true)
        supportDirectory = support
        store = TranscriptStore(roots: TranscriptStore.defaultRoots(),
                                cacheURL: support.appendingPathComponent("usage-cache.json"))
        prices = PriceTable.loadOrInstall(at: support.appendingPathComponent("pricing.json"))
        billingDay = d.object(forKey: "billingDay") as? Int ?? 1
        weekStart = WeekStart(rawValue: d.string(forKey: "weekStart") ?? "") ?? .planReset
        planPriceOverride = d.object(forKey: "planPriceOverride") as? Double ?? 0
        fetchPlanLimits = d.object(forKey: "fetchPlanLimits") as? Bool ?? true
        planRefreshMinutes = d.object(forKey: "planRefreshMinutes") as? Int ?? 5
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .limits
        if !snapshot { start() }
    }

    /// Injects plan data without a network call (snapshot rendering only).
    func setPlanStatusForSnapshot(_ status: PlanStatus) {
        planStatus = status
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Refresh loops

    private func start() {
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTranscripts()
                try? await Task.sleep(for: .seconds(30))
            }
        })
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = Date()
                let interval = TimeInterval(max(self.planRefreshMinutes, 1) * 60)
                if self.fetchPlanLimits,
                   self.lastPlanFetch.map({ Date().timeIntervalSince($0) >= interval }) ?? true {
                    await self.refreshPlan()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        })
    }

    func refreshTranscripts(full: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        let result = full ? await store.rescanAll() : await store.refresh()
        entries = result
        lastScan = Date()
        now = Date()
        isScanning = false
    }

    func refreshPlan() async {
        guard fetchPlanLimits, !snapshot else { return }
        lastPlanFetch = Date()
        do {
            planStatus = try await PlanUsageClient.fetch()
            planError = nil
        } catch {
            planError = error.localizedDescription
        }
    }

    func refreshAll() async {
        now = Date()
        async let t: Void = refreshTranscripts()
        async let p: Void = refreshPlan()
        _ = await (t, p)
    }

    func reloadPrices() {
        prices = PriceTable.loadOrInstall(at: pricesURL)
    }

    // MARK: - Derived

    var builder: ReportBuilder {
        ReportBuilder(prices: prices, billingDay: billingDay, weekStart: weekStart,
                      planWeekStart: planStatus?.weeklyWindowStart)
    }

    func report(_ period: ReportPeriod) -> PeriodReport {
        builder.report(period, entries: entries, now: now)
    }

    var plan: Plan? { planStatus?.plan }

    var effectivePlanPrice: Double? {
        planPriceOverride > 0 ? planPriceOverride : plan?.listMonthlyPrice
    }

    var billing: BillingComparison {
        builder.billingComparison(entries: entries, now: now, planPrice: effectivePlanPrice)
    }

    var sessionLimit: PlanLimit? { planStatus?.limits.first { $0.group == "session" } }
    var weeklyLimit: PlanLimit? { planStatus?.limits.first { $0.id.hasPrefix("weekly_all") } }

    var menuBarText: String {
        switch menuBarStyle {
        case .limits:
            if let s = sessionLimit, let w = weeklyLimit {
                return "\(Format.percent(s.percentUsed)) · \(Format.percent(w.percentUsed))"
            }
            return Format.tokens(report(.today).totals.total)
        case .tokensToday: return Format.tokens(report(.today).totals.total)
        case .costToday: return Format.usd(report(.today).totals.cost.total)
        case .iconOnly: return ""
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                planError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }
}

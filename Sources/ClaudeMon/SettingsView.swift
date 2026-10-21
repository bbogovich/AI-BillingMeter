import ClaudeMonCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Billing") {
                Picker("Billing month starts on day", selection: $model.billingDay) {
                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                }
                LabeledContent("Monthly plan price") {
                    HStack {
                        TextField("", value: $model.planPriceOverride, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("USD")
                    }
                }
                Text(planPriceHint).font(.caption).foregroundStyle(.secondary)
            }
            Section("Week") {
                Picker("Week starts", selection: $model.weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Plan limits") {
                Toggle("Fetch session and weekly limits from claude.ai", isOn: $model.fetchPlanLimits)
                Stepper("Refresh every \(model.planRefreshMinutes) min", value: $model.planRefreshMinutes, in: 1...60)
                Text("Uses the login Claude Code stores in your Keychain, read through the same `security` tool Claude Code uses, so macOS does not ask for access. Read-only: the token is never refreshed or sent anywhere but api.anthropic.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Picker("Show", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in model.launchAtLogin = v }
            }
            Section("History") {
                // trace: R-CMUI-005 <- F-10.CR-1, F-14
                Stepper(value: $model.detailedHistoryMonths, in: HistoryPolicy.range) {
                    Text(historyLabel)
                }
                Text(historyStatus).font(.caption).foregroundStyle(.secondary)
                Text("Older months are kept as weekly totals per model and project. Raising this later does not bring back detail that was already summarized.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                LabeledContent("Prices as of", value: model.prices.asOf)
                HStack {
                    Button("Edit pricing.json") { NSWorkspace.shared.open(model.pricesURL) }
                    Button("Reload prices") { model.reloadPrices() }
                    Button("Rescan transcripts") { Task { await model.refreshTranscripts(full: true) } }
                }
                Button("Show data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.supportDirectory])
                }
                Text("Token counts come from Claude Code transcripts in ~/.claude/projects. Usage from claude.ai chat or other devices counts toward plan limits but has no local transcript, so it is not in the token totals.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = model.launchAtLogin }
    }

    private var historyLabel: String {
        switch model.detailedHistoryMonths {
        case 0: "Detailed history: this month only"
        case 1: "Detailed history: this month and last month"
        case let n: "Detailed history: this month and \(n) before it"
        }
    }

    private var historyStatus: String {
        let weeks = Set(model.summaries.map(\.weekStart)).count
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.cacheBytes), countStyle: .file)
        var text = "\(model.entries.count.formatted()) detailed calls · \(weeks) summarized weeks · cache \(size)"
        if let before = model.summarizedBefore {
            text += " · summarized before \(before.formatted(date: .abbreviated, time: .omitted))"
        }
        return text
    }

    private var planPriceHint: String {
        if let p = model.plan?.listMonthlyPrice {
            return "0 = use the \(model.plan!.displayName) list price (\(Format.usd(p))/month)."
        }
        return "Enter your subscription price; 0 = auto-detect from your plan."
    }
}

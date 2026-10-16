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
                Text("Uses the login Claude Code stores in your Keychain (read-only; the token is never refreshed or sent anywhere but api.anthropic.com). macOS asks once for Keychain access — choose Always Allow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Picker("Show", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in model.launchAtLogin = v }
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

    private var planPriceHint: String {
        if let p = model.plan?.listMonthlyPrice {
            return "0 = use the \(model.plan!.displayName) list price (\(Format.usd(p))/month)."
        }
        return "Enter your subscription price; 0 = auto-detect from your plan."
    }
}

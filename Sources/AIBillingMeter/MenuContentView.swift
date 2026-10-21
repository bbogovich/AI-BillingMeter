import BillingMeterCore
import SwiftUI

struct MenuContentView: View {
    @Bindable var model: AppModel
    @Environment(\.showSettings) private var showSettings
    @AppStorage("selectedPeriod") private var period: ReportPeriod = .today
    @AppStorage("chartMetric") private var metric: ChartMetric = .tokens
    @AppStorage("breakdown") private var breakdownByProject = false

    var body: some View {
        let report = model.report(period)
        VStack(alignment: .leading, spacing: 12) {
            header
            PlanLimitsSection(model: model)
            Divider()
            Picker("Period", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            periodHeader(report)
            if let before = report.summarizedBefore {
                // trace: R-CMUI-014 <- F-14
                Label("Includes weekly summaries before \(before.formatted(.dateTime.month(.abbreviated).day()))",
                      systemImage: "calendar.badge.clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            TotalsGrid(totals: report.totals)

            HStack {
                Text(report.bucketUnit == .hour ? "Per hour" : report.bucketUnit == .month ? "Per month" : "Per day")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Metric", selection: $metric) {
                    ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            UsageChart(report: report, metric: metric)

            if period == .billing {
                BillingSection(billing: model.billing, planName: model.plan?.displayName)
            }

            // trace: F-15, F-16 — All lists every project, so each one's total cost can be found.
            BreakdownSection(rows: breakdownByProject ? report.byProject : report.byModel,
                             byProject: $breakdownByProject, showAll: period == .all)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .fitsMenuBarWindow()
        .task { await model.refreshAll() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text("AI Billing Meter").font(.headline)
            if let plan = model.plan {
                Text(plan.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button {
                Task { await model.refreshAll() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
        }
    }

    private func periodHeader(_ r: PeriodReport) -> some View {
        let i = r.interval
        let text: String = switch r.period {
        case .today: i.start.formatted(.dateTime.weekday(.wide).month().day())
        case .week, .billing:
            "\(i.start.formatted(.dateTime.month(.abbreviated).day().hour())) – " +
            "\(i.end.formatted(.dateTime.month(.abbreviated).day().hour()))"
        case .all:
            "Since \(i.start.formatted(.dateTime.month(.wide).year()))"
        }
        return HStack(alignment: .firstTextBaseline) {
            Text(Format.tokens(r.totals.total))
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            Text("tokens").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.usd(r.totals.cost.total)).font(.title3.monospacedDigit())
                Text("at API rates").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .topLeading) {
            Text(text).font(.caption2).foregroundStyle(.tertiary).offset(y: -12)
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack {
            if let scan = model.lastScan {
                Text("Updated \(scan.formatted(date: .omitted, time: .shortened)) · \(model.entries.count.formatted()) calls tracked")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings…") { showSettings() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

struct PlanLimitsSection: View {
    let model: AppModel

    var body: some View {
        if !model.fetchPlanLimits {
            Text("Plan limits are off (Settings).").font(.caption).foregroundStyle(.secondary)
        } else if let status = model.planStatus, !status.limits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(status.limits) { LimitRow(limit: $0) }
                if let err = model.planError {
                    Label(err, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if let err = model.planError {
            Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack { ProgressView().controlSize(.small); Text("Loading plan limits…").font(.caption) }
        }
    }
}

struct LimitRow: View {
    let limit: PlanLimit

    var body: some View {
        let (color, icon) = Theme.status(forPercentUsed: limit.percentUsed)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.title).font(.callout)
                Spacer()
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text("\(Format.percent(limit.percentRemaining)) left")
                    .font(.callout.monospacedDigit().weight(.medium))
            }
            ProgressView(value: min(limit.percentUsed, 100), total: 100)
                .tint(color)
            Text("\(Format.percent(limit.percentUsed)) used · \(Format.resetText(limit.resetsAt))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct TotalsGrid: View {
    let totals: TokenTotals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            row("Input", totals.input, totals.cost.input)
            row("Output", totals.output, totals.cost.output)
            row("Cache write", totals.cacheWrite, totals.cost.cacheWrite)
            row("Cache read", totals.cacheRead, totals.cost.cacheRead)
            GridRow {
                Text("Requests").foregroundStyle(.secondary)
                Text(totals.requests.formatted()).monospacedDigit().gridColumnAlignment(.trailing)
                if totals.cost.webSearch > 0 {
                    Text("+ \(Format.usd(totals.cost.webSearch)) web search").foregroundStyle(.secondary)
                } else { Text("") }
            }
            if totals.unpricedTokens > 0 {
                GridRow {
                    Text("Unpriced").foregroundStyle(.secondary)
                    Text(Format.tokens(totals.unpricedTokens)).monospacedDigit()
                    Text("model not in pricing.json").foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    private func row(_ name: String, _ tokens: Int, _ cost: Double) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(Format.tokens(tokens)).monospacedDigit().gridColumnAlignment(.trailing)
            Text(Format.usd(cost)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

struct BillingSection: View {
    let billing: BillingComparison
    let planName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Plan vs. API metered billing").font(.callout.weight(.semibold))
                Spacer()
                Text("\(Format.percent(billing.elapsedFraction * 100)) of period elapsed")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text("API cost so far").foregroundStyle(.secondary)
                    Text(Format.usd(billing.apiCostToDate)).monospacedDigit()
                }
                GridRow {
                    Text("Projected for period").foregroundStyle(.secondary)
                    Text(Format.usd(billing.projectedApiCost)).monospacedDigit()
                }
                GridRow {
                    Text("\(planName ?? "Plan") price").foregroundStyle(.secondary)
                    Text(billing.planPrice.map(Format.usd) ?? "set in Settings").monospacedDigit()
                }
            }
            .font(.caption)
            if let savings = billing.projectedSavings {
                let good = savings >= 0
                Label(good
                      ? "Plan saves ~\(Format.usd(savings)) vs. API this period"
                      : "API billing would be ~\(Format.usd(-savings)) cheaper this period",
                      systemImage: good ? "checkmark.seal.fill" : "info.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(good ? Theme.good : Theme.warning)
                if let x = billing.valueMultipleToDate {
                    Text(String(format: "%.1f× plan price consumed at API rates so far", x))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BreakdownSection: View {
    let rows: [BreakdownRow]
    @Binding var byProject: Bool
    /// List every row (scrolling past a few) instead of the top six.
    var showAll = false

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(byProject ? "By project" : "By model").font(.caption.weight(.semibold))
                    Spacer()
                    Button(byProject ? "Show models" : "Show projects") { byProject.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
                if showAll && rows.count > 6 {
                    // Fixed height, so the panel does not grow with the number of projects.
                    ScrollView { list(rows[...]).padding(.trailing, 12) }
                        .frame(height: 6 * 17)
                    Text("\(rows.count) \(byProject ? "projects" : "models") · total \(Format.usd(rows.map(\.totals.cost.total).reduce(0, +)))")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    list(rows.prefix(6))
                }
            }
        }
    }

    private func list(_ rows: ArraySlice<BreakdownRow>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { r in
                HStack {
                    if !byProject {
                        Circle()
                            .fill(Theme.color(forFamily: ReportBuilder.family(of: r.name)))
                            .frame(width: 7, height: 7)
                    }
                    Text(r.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Format.tokens(r.totals.total)).monospacedDigit().foregroundStyle(.secondary)
                    Text(Format.usd(r.totals.cost.total)).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                .font(.caption)
                .frame(height: 13)
                .help(r.detail ?? r.name)
            }
        }
    }
}

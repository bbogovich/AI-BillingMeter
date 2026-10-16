import Charts
import ClaudeMonCore
import SwiftUI

enum ChartMetric: String, CaseIterable, Identifiable {
    case tokens = "Tokens", cost = "API cost"
    var id: String { rawValue }
}

/// Stacked bars per hour (today) or day (week / billing month), one segment per model family.
struct UsageChart: View {
    let report: PeriodReport
    let metric: ChartMetric
    @State private var selected: Date?

    private var families: [String] {
        let present = Set(report.buckets.map(\.family))
        return Theme.familyOrder.filter(present.contains)
    }

    private func value(_ b: UsageBucket) -> Double {
        metric == .tokens ? Double(b.tokens) : b.cost
    }

    private func label(_ v: Double) -> String {
        metric == .tokens ? Format.tokens(Int(v)) : Format.usd(v)
    }

    /// The bucket under the pointer, snapped to the bar's start.
    private var selectedBucketStart: Date? {
        guard let selected else { return nil }
        return report.buckets.map(\.start).filter { $0 <= selected }.max()
            .flatMap { start in
                let span: TimeInterval = report.bucketUnit == .hour ? 3600 : 86_400
                return selected.timeIntervalSince(start) < span ? start : nil
            }
    }

    var body: some View {
        if report.buckets.isEmpty {
            Text("No usage in this period yet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(report.buckets) { b in
                BarMark(x: .value("Time", b.start, unit: report.bucketUnit),
                        y: .value(metric.rawValue, value(b)))
                    .foregroundStyle(by: .value("Model", b.family))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .opacity(selectedBucketStart == nil || selectedBucketStart == b.start ? 1 : 0.45)
            }
            if let start = selectedBucketStart {
                RuleMark(x: .value("Time", start, unit: report.bucketUnit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(for: start)
                    }
            }
        }
        .chartForegroundStyleScale(domain: families, range: families.map(Theme.color(forFamily:)))
        .chartXScale(domain: report.chartDomain)
        .chartXSelection(value: $selected)
        .chartXAxis {
            if report.bucketUnit == .hour {
                AxisMarks(values: .stride(by: .hour, count: 6)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.hour())
                }
            } else if report.period == .week {
                AxisMarks(values: .stride(by: .day)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(label(d)) }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 6)
        .frame(height: 150)
    }

    private func tooltip(for start: Date) -> some View {
        let rows = report.buckets.filter { $0.start == start }
        let total = rows.map(value).reduce(0, +)
        let title = report.bucketUnit == .hour
            ? start.formatted(.dateTime.hour().minute())
            : start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(title) · \(label(total))").font(.caption.bold())
            ForEach(Theme.familyOrder.filter { f in rows.contains { $0.family == f } }, id: \.self) { f in
                let v = rows.filter { $0.family == f }.map(value).reduce(0, +)
                HStack(spacing: 4) {
                    Circle().fill(Theme.color(forFamily: f)).frame(width: 6, height: 6)
                    Text(f).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(label(v)).font(.caption2.monospacedDigit())
                }
            }
        }
        .padding(6)
        .frame(minWidth: 130)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
    }
}

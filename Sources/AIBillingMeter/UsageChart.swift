import Charts
import BillingMeterCore
import SwiftUI

enum ChartMetric: String, CaseIterable, Identifiable {
    case tokens = "Tokens", cost = "API cost"
    var id: String { rawValue }
}

/// Stacked bars per hour (today), day (week / billing month) or month (all), one segment per model
/// family. More than `visibleMonths` months scroll horizontally, opening at the latest (F-15).
struct UsageChart: View {
    let report: PeriodReport
    let metric: ChartMetric
    @State private var selected: Date?

    /// Months shown at once on the All tab; more than this scroll.
    static let visibleMonths = 12

    private var monthCount: Int {
        Calendar.current.dateComponents([.month], from: report.chartDomain.lowerBound,
                                        to: report.chartDomain.upperBound).month ?? 0
    }

    private var scrolls: Bool { report.bucketUnit == .month && monthCount > Self.visibleMonths }

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
                Calendar.current.dateInterval(of: report.bucketUnit, for: start)?.contains(selected) == true
                    ? start : nil
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
            } else if report.bucketUnit == .month {
                AxisMarks(values: .stride(by: .month, count: monthCount > 6 || scrolls ? 2 : 1)) { v in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(centered: true) {
                        if let d = v.as(Date.self) {
                            // The year on January and on the first month shown.
                            let month = Calendar.current.component(.month, from: d)
                            Text(month == 1 || v.index == 0
                                 ? d.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                                 : d.formatted(.dateTime.month(.abbreviated)))
                        }
                    }
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
        .modifier(MonthScrolling(enabled: scrolls, domainEnd: report.chartDomain.upperBound))
        .frame(height: 150)
    }

    private func tooltip(for start: Date) -> some View {
        let rows = report.buckets.filter { $0.start == start }
        let total = rows.map(value).reduce(0, +)
        let title = switch report.bucketUnit {
        case .hour: start.formatted(.dateTime.hour().minute())
        case .month: start.formatted(.dateTime.month(.wide).year())
        default: start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
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

/// Horizontal scrolling for a long monthly chart: twelve months visible, opening at the latest.
private struct MonthScrolling: ViewModifier {
    let enabled: Bool
    let domainEnd: Date

    func body(content: Content) -> some View {
        if enabled {
            let length = Double(UsageChart.visibleMonths) * 30.44 * 86_400
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: length)
                .chartScrollPosition(initialX: domainEnd.addingTimeInterval(-length))
        } else {
            content
        }
    }
}

import SwiftUI
import Charts

enum StatRange: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", twelve = "12 weeks", all = "All time"
    var id: String { rawValue }
}

enum StatMetric: String, CaseIterable, Identifiable {
    case days = "Days", events = "Events", hours = "Hours"
    var id: String { rawValue }
}

private struct StatPoint: Identifiable {
    let id = UUID()
    let bucket: String
    let order: Int
    let category: String
    let value: Double
}

/// Where your time goes, by category.
struct StatsView: View {
    @EnvironmentObject var model: PlannerModel
    @State private var range: StatRange = .week
    @State private var metric: StatMetric = .days
    @State private var anchor = Date()

    private enum Bucket { case day, week, month }

    var body: some View {
        let t = model.theme
        let win = window()
        let recs = records(from: win.from, to: win.to)
        let total = recs.reduce(0) { $0 + $1.value }
        let byCat = Dictionary(grouping: recs, by: { $0.cat }).mapValues { $0.reduce(0) { $0 + $1.value } }
        let ranked = byCat.sorted { $0.value > $1.value }
        let evCount = expandEvents(model.events, from: win.from, to: win.to).count
        let spanDays = max(1, Week.days(from: win.from, to: win.to) + 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Range", selection: $range) {
                        ForEach(StatRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    Picker("Count", selection: $metric) {
                        ForEach(StatMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                HStack {
                    if range == .week || range == .month {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    }
                    Text(win.label).font(.headline)
                    Spacer()
                }

                if total == 0 {
                    VStack(spacing: 8) {
                        Text("Nothing to show here yet").font(.title3.bold())
                        Text(metric == .hours
                             ? "Hours only count when you add them to an event (open an event and pick hours)."
                             : "Switch to Events mode on the Planner, then tap a line to type an event or drag down over your handwriting to tag it.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(t.muted))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color(t.header), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    HStack(spacing: 12) {
                        tile("Total", format(total))
                        tile("Events", "\(evCount)")
                        tile("Average per day", String(format: "%.1f", total / Double(spanDays)))
                        tile("Top category", model.name(for: ranked[0].key), color: Color(model.color(for: ranked[0].key)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("By category").font(.headline)
                        ForEach(ranked, id: \.key) { item in
                            HStack(spacing: 10) {
                                Circle().fill(Color(model.color(for: item.key))).frame(width: 12, height: 12)
                                Text(model.name(for: item.key)).frame(width: 150, alignment: .leading).lineLimit(1)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(t.line))
                                        Capsule().fill(Color(model.color(for: item.key)))
                                            .frame(width: g.size.width * CGFloat(item.value / ranked[0].value))
                                    }
                                }
                                .frame(height: 10)
                                Text("\(format(item.value))  \(Int((item.value / total * 100).rounded()))%")
                                    .monospacedDigit()
                                    .frame(width: 130, alignment: .trailing)
                            }
                        }
                    }
                    .padding()
                    .background(Color(t.header), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading) {
                        Text("\(metric.rawValue) over time").font(.headline)
                        let points = chartPoints(recs, win)
                        let names = model.categories.map { $0.name }
                        let colors = model.categories.map { Color($0.uiColor) }
                        Chart(points) { p in
                            BarMark(x: .value("When", p.bucket), y: .value(metric.rawValue, p.value))
                                .foregroundStyle(by: .value("Category", p.category))
                        }
                        .chartForegroundStyleScale(domain: names, range: colors)
                        .frame(height: 260)
                    }
                    .padding()
                    .background(Color(t.header), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color(t.ink))
        .background(Color(t.paper))
    }

    private func tile(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption).foregroundStyle(Color(model.theme.muted))
            Text(value).font(.title2.bold()).foregroundStyle(color ?? Color(model.theme.ink)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(model.theme.header), in: RoundedRectangle(cornerRadius: 12))
    }

    private func format(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        let n = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        switch metric {
        case .days: return n + (r == 1 ? " day" : " days")
        case .events: return n + (r == 1 ? " event" : " events")
        case .hours: return n + " h"
        }
    }

    private func shift(_ n: Int) {
        let cal = Week.calendar
        anchor = range == .week
            ? (cal.date(byAdding: .day, value: 7 * n, to: anchor) ?? anchor)
            : (cal.date(byAdding: .month, value: n, to: anchor) ?? anchor)
    }

    private func window() -> (from: Date, to: Date, label: String, bucket: Bucket) {
        let cal = Week.calendar
        switch range {
        case .week:
            let f = Week.start(of: anchor)
            return (f, Week.day(6, of: f), Week.range(f) + ", \(cal.component(.year, from: f))", .day)
        case .month:
            let f = Week.monthStart(anchor)
            let t = cal.date(byAdding: DateComponents(month: 1, day: -1), to: f) ?? f
            return (f, t, Week.monthYear(f), .day)
        case .twelve:
            let t = Week.day(6, of: Week.start(of: Date()))
            return (Week.day(-83, of: t), t, "Last 12 weeks", .week)
        case .all:
            let starts = model.events.map { $0.start }
            // repeating events with no end date count up to today
            let ends = model.events.map { $0.repeats ? Date() : $0.end }
            let f = starts.min() ?? Date()
            let t = max(ends.max() ?? Date(), f)
            return (f, t, "All time", Week.days(from: f, to: t) > 26 * 7 ? .month : .week)
        }
    }

    private struct Rec { let date: Date; let cat: String; let value: Double }

    private func records(from: Date, to: Date) -> [Rec] {
        var out: [Rec] = []
        for e in expandEvents(model.events, from: from, to: to) {
            switch metric {
            case .days:
                for k in 0..<e.days {
                    let d = Week.day(k, of: e.start)
                    if d >= from && d <= to { out.append(Rec(date: d, cat: e.cat, value: 1)) }
                }
            case .events:
                if e.start >= from && e.start <= to { out.append(Rec(date: e.start, cat: e.cat, value: 1)) }
            case .hours:
                if e.hrs > 0 && e.start >= from && e.start <= to { out.append(Rec(date: e.start, cat: e.cat, value: e.hrs)) }
            }
        }
        return out
    }

    private func chartPoints(_ recs: [Rec], _ win: (from: Date, to: Date, label: String, bucket: Bucket)) -> [StatPoint] {
        let cal = Week.calendar
        // the buckets, in order
        var buckets: [(key: Date, label: String)] = []
        switch win.bucket {
        case .day:
            var d = win.from
            while d <= win.to {
                buckets.append((d, range == .week ? Week.weekday(d) : "\(cal.component(.day, from: d))"))
                d = Week.day(1, of: d)
            }
        case .week:
            var d = Week.start(of: win.from)
            while d <= win.to {
                buckets.append((d, "\(Week.monthShort(d)) \(cal.component(.day, from: d))"))
                d = Week.adding(1, to: d)
            }
        case .month:
            var d = Week.monthStart(win.from)
            while d <= win.to {
                buckets.append((d, Week.monthShort(d)))
                d = cal.date(byAdding: .month, value: 1, to: d) ?? win.to.addingTimeInterval(1)
            }
        }
        func bucketKey(_ date: Date) -> Date {
            switch win.bucket {
            case .day: return cal.startOfDay(for: date)
            case .week: return Week.start(of: date)
            case .month: return Week.monthStart(date)
            }
        }
        var sums: [Date: [String: Double]] = [:]
        for r in recs { sums[bucketKey(r.date), default: [:]][r.cat, default: 0] += r.value }

        var points: [StatPoint] = []
        for (i, b) in buckets.enumerated() {
            let cats = sums[b.key] ?? [:]
            if cats.isEmpty {
                points.append(StatPoint(bucket: b.label, order: i, category: model.categories.first?.name ?? "", value: 0))
            }
            for (cat, v) in cats {
                points.append(StatPoint(bucket: b.label, order: i, category: model.name(for: cat), value: v))
            }
        }
        return points
    }
}

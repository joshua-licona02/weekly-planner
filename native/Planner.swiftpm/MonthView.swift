import SwiftUI

/// Full month calendar. Multi-day events show as one bar across their days.
struct MonthView: View {
    @EnvironmentObject var model: PlannerModel
    @State private var picking = false
    @State private var pickMonth = 1
    @State private var pickYear = 2026
    @State private var selectedDay: DayPick?

    private func shift(_ n: Int) {
        model.monthAnchor = Week.calendar.date(byAdding: .month, value: n, to: Week.monthStart(model.monthAnchor)) ?? model.monthAnchor
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { withAnimation { shift(-1) } } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title)
            }
            Button {
                let cal = Week.calendar
                pickMonth = cal.component(.month, from: model.monthAnchor)
                pickYear = cal.component(.year, from: model.monthAnchor)
                picking = true
            } label: {
                HStack(spacing: 6) {
                    Text(Week.monthYear(model.monthAnchor)).font(.title2.bold())
                    Image(systemName: "chevron.down").font(.callout.weight(.bold))
                }
            }
            Button { withAnimation { shift(1) } } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title)
            }
            Spacer()
            Button("This month") { model.monthAnchor = Date() }
                .buttonStyle(.bordered)
            Button {
                let cal = Week.calendar
                let today = cal.startOfDay(for: Date())
                let inThisMonth = cal.isDate(today, equalTo: model.monthAnchor, toGranularity: .month)
                model.beginNew(date: inThisMonth ? today : Week.monthStart(model.monthAnchor))
            } label: {
                Label("Add event", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .tint(Color(model.theme.accent))
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var monthPicker: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $pickMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Week.calendar.monthSymbols[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Year", selection: $pickYear) {
                    ForEach(2000...2100, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding()
            .navigationTitle("Choose a month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        if let d = Week.calendar.date(from: DateComponents(year: pickYear, month: pickMonth, day: 1)) {
                            model.monthAnchor = d
                        }
                        picking = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    withAnimation { shift(v.translation.width < 0 ? 1 : -1) }   // swipe left = next month
                }
        )
        .sheet(isPresented: $picking) { monthPicker }
        .sheet(item: $selectedDay) { pick in
            DayCard(date: pick.date) { action in
                selectedDay = nil
                // let this card close before the next one opens
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    switch action {
                    case .add: model.beginNew(date: pick.date)
                    case .edit(let e): model.beginEdit(e)
                    case .openWeek:
                        model.commands.send(.show(pick.date))
                        model.screen = .planner
                    case .close:
                        break
                    }
                }
            }
            .environmentObject(model)
        }
    }

    @ViewBuilder private var grid: some View {
        let first = Week.monthStart(model.monthAnchor)
        let last = Week.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) ?? first
        let gridStart = Week.start(of: first)
        let weeks = Week.days(from: gridStart, to: Week.start(of: last)) / 7 + 1
        let month = Week.calendar.component(.month, from: first)
        let t = model.theme

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Week.weekday(Week.day(i, of: gridStart)).uppercased())
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .background(Color(t.header))
            ForEach(0..<weeks, id: \.self) { w in
                MonthWeekRow(weekStart: Week.adding(w, to: gridStart), month: month, maxLanes: weeks > 5 ? 3 : 4,
                             onDay: { selectedDay = DayPick(date: $0) })
            }
        }
        .foregroundStyle(Color(t.ink))
        .background(Color(t.paper))
        .overlay(Rectangle().stroke(Color(t.border), lineWidth: 2))
        .padding(10)
    }
}

private struct MonthSeg: Identifiable {
    let id: String
    let start: Int
    let end: Int
    let lane: Int
    let event: PlannerEvent
}

private struct MonthLayout {
    var segs: [MonthSeg] = []
    var hidden: [Int] = Array(repeating: 0, count: 7)
}

private struct MonthWeekRow: View {
    @EnvironmentObject var model: PlannerModel
    let weekStart: Date
    let month: Int
    let maxLanes: Int
    let onDay: (Date) -> Void

    var body: some View {
        let lay = layout()
        let t = model.theme
        GeometryReader { geo in
            let colW = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(i, hidden: lay.hidden[i])
                            .frame(width: colW, height: geo.size.height)
                    }
                }
                ForEach(lay.segs) { s in
                    bar(s)
                        .frame(width: max(colW * CGFloat(s.end - s.start + 1) - 8, 10), height: 20)
                        .offset(x: colW * CGFloat(s.start) + 4, y: 34 + CGFloat(s.lane) * 23)
                        .onTapGesture { model.beginEdit(s.event) }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(t.line)).frame(height: 1) }
    }

    private func dayCell(_ i: Int, hidden: Int) -> some View {
        let date = Week.day(i, of: weekStart)
        let cal = Week.calendar
        let inMonth = cal.component(.month, from: date) == month
        let isToday = cal.isDateInToday(date)
        let t = model.theme
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .frame(width: 28, height: 28)
                .background(isToday ? Color(t.accent) : Color.clear, in: Circle())
                .foregroundStyle(isToday ? Color.white : Color(t.ink).opacity(inMonth ? 1 : 0.4))
            Spacer(minLength: 0)
            if hidden > 0 {
                Text("+\(hidden) more").font(.caption2).foregroundStyle(Color(t.muted))
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.gray.opacity(0.08))
        .overlay(alignment: .trailing) { Rectangle().fill(Color(t.line)).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onDay(date) }
    }

    private func bar(_ s: MonthSeg) -> some View {
        let c = Color(model.color(for: s.event.cat))
        let untitled = s.event.title.isEmpty
        let label = s.event.label(categoryName: model.name(for: s.event.cat))
        return HStack(spacing: 0) {
            Rectangle().fill(c).frame(width: 4)
            Text(label)
                .font(.caption.weight(.semibold))
                .italic(untitled)
                .lineLimit(1)
                .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .background(c.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func layout() -> MonthLayout {
        let weekEnd = Week.day(6, of: weekStart)
        let evs = expandEvents(model.events, from: weekStart, to: weekEnd)
            .sorted { a, b in a.date == b.date ? a.days > b.days : a.date < b.date }
        var laneEnd: [Int] = []
        var out = MonthLayout()
        for e in evs {
            let off = Week.days(from: weekStart, to: e.start)
            let si = max(0, off), ei = min(6, off + e.days - 1)
            var lane = laneEnd.firstIndex(where: { $0 < si }) ?? laneEnd.count
            if lane == laneEnd.count { laneEnd.append(ei) } else { laneEnd[lane] = ei }
            if lane >= maxLanes {
                for d in si...ei { out.hidden[d] += 1 }
                continue
            }
            lane = min(lane, maxLanes - 1)
            out.segs.append(MonthSeg(id: e.id, start: si, end: ei, lane: lane, event: e))
        }
        return out
    }
}

struct DayPick: Identifiable {
    let date: Date
    var id: String { Week.key(date) }
}

/// Tapping a day in Month view: its events, add one, or open that week's pages.
struct DayCard: View {
    enum Action { case add, edit(PlannerEvent), openWeek, close }

    @EnvironmentObject var model: PlannerModel
    let date: Date
    let onAction: (Action) -> Void

    var body: some View {
        let dayEvents = expandEvents(model.events, from: date, to: date)
            .sorted { ($0.startMin ?? -1, $0.title) < ($1.startMin ?? -1, $1.title) }
        NavigationStack {
            List {
                Section {
                    if dayEvents.isEmpty {
                        Text("Nothing planned yet.").foregroundStyle(.secondary)
                    }
                    ForEach(dayEvents) { e in
                        Button { onAction(.edit(e)) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(model.color(for: e.cat)))
                                    .frame(width: 6, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title.isEmpty ? model.name(for: e.cat) : e.title)
                                        .foregroundStyle(Color.primary)
                                    Text(details(e)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if e.repeats { Image(systemName: "repeat").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section {
                    Button { onAction(.add) } label: {
                        Label("Add event", systemImage: "plus.circle.fill")
                    }
                    Button { onAction(.openWeek) } label: {
                        Label("Open this week in the planner", systemImage: "book")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onAction(.close) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    private func details(_ e: PlannerEvent) -> String {
        var parts = [model.name(for: e.cat)]
        if let t = e.timeLabel { parts.append(t) } else { parts.append("All day") }
        if e.days > 1 { parts.append("\(e.days) days") }
        return parts.joined(separator: " · ")
    }
}

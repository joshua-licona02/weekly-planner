import SwiftUI

/// The card for typing / editing an event (works like Apple Calendar's event card).
struct EventEditor: View {
    @EnvironmentObject var model: PlannerModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EventDraft
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var repeatRule: String
    @State private var hasUntil: Bool
    @State private var until: Date
    @State private var open: Field?
    @FocusState private var nameFocused: Bool

    private enum Field { case start, end, until }
    private let hourOptions: [Double] = [1, 2, 3, 4, 6, 8]

    init(draft: EventDraft) {
        let e = draft.event
        let cal = Week.calendar
        let firstDay = e.start
        let lastDay = e.end
        _draft = State(initialValue: draft)
        _allDay = State(initialValue: e.startMin == nil)
        _start = State(initialValue: cal.date(byAdding: .minute, value: e.startMin ?? 9 * 60, to: firstDay) ?? firstDay)
        _end = State(initialValue: cal.date(byAdding: .minute, value: e.endMin ?? 10 * 60, to: lastDay) ?? lastDay)
        _repeatRule = State(initialValue: e.repeatRule)
        _hasUntil = State(initialValue: e.until != nil)
        _until = State(initialValue: e.until.flatMap { Week.date(fromKey: $0) }
                       ?? (cal.date(byAdding: .month, value: 3, to: firstDay) ?? firstDay))
        _open = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event name (e.g. Golf with Dave)", text: $draft.event.title)
                        .font(.title3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                        ForEach(model.categories) { c in
                            Button {
                                draft.event.cat = c.id
                            } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(c.uiColor)).frame(width: 14, height: 14)
                                    Text(c.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if draft.event.cat == c.id { Image(systemName: "checkmark") }
                                }
                                .padding(10)
                                .background(Color(c.uiColor).opacity(draft.event.cat == c.id ? 0.22 : 0.08),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("When") {
                    Toggle("All day", isOn: $allDay)
                    dateRow("Starts", start, .start)
                    if open == .start {
                        DatePicker("Starts", selection: $start,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    dateRow("Ends", end, .end)
                    if open == .end {
                        DatePicker("Ends", selection: $end, in: start...,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.options) { o in Text(o.name).tag(o.id) }
                    }
                    if repeatRule != "none" {
                        Toggle("End repeat", isOn: $hasUntil)
                        if hasUntil {
                            dateRow("Repeat until", until, .until)
                            if open == .until {
                                DatePicker("Repeat until", selection: $until, in: start..., displayedComponents: [.date])
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                Section("On the page") {
                    Stepper(value: $draft.event.lines, in: 1...Page.lines) {
                        Text(draft.event.lines == 1 ? "1 line tall" : "\(draft.event.lines) lines tall")
                    }
                    if allDay {
                        Picker("Hours (for stats)", selection: $draft.event.hrs) {
                            Text("None").tag(0.0)
                            ForEach(hourOptions, id: \.self) { h in Text("\(Int(h)) h").tag(h) }
                        }
                    } else {
                        LabeledContent("Hours (for stats)", value: String(format: "%.2g h", timedHours))
                    }
                }

                if !draft.isNew {
                    Section {
                        Button(draft.event.repeats ? "Delete event (all repeats)" : "Delete event", role: .destructive) {
                            model.delete(draft.event.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isNew ? "Add" : "Save") { save() }
                }
            }
            .onChange(of: start) { newStart in
                if end < newStart { end = allDay ? newStart : newStart.addingTimeInterval(3600) }
                if until < newStart { until = newStart }
            }
            .onAppear {
                // New events: put the cursor in the name and bring up the keyboard right away.
                if draft.isNew {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true }
                }
            }
        }
    }

    private var timedHours: Double {
        max(0, (end.timeIntervalSince(start) / 3600 * 4).rounded() / 4)
    }

    private func dateRow(_ label: String, _ value: Date, _ field: Field) -> some View {
        Button {
            nameFocused = false
            withAnimation { open = (open == field) ? nil : field }
        } label: {
            HStack {
                Text(label).foregroundStyle(Color.primary)
                Spacer()
                Text(display(value, timed: !allDay && field != .until))
                    .foregroundStyle(open == field ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func display(_ d: Date, timed: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = timed ? "EEE, MMM d, yyyy  h:mm a" : "EEE, MMM d, yyyy"
        return f.string(from: d)
    }

    private func save() {
        let cal = Week.calendar
        var e = draft.event
        let finish = max(end, start)
        e.date = Week.key(start)
        e.days = max(1, Week.days(from: start, to: finish) + 1)
        if allDay {
            e.startMin = nil
            e.endMin = nil
        } else {
            e.startMin = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
            e.endMin = cal.component(.hour, from: finish) * 60 + cal.component(.minute, from: finish)
            e.hrs = timedHours
        }
        e.repeatRule = repeatRule
        e.until = (repeatRule != "none" && hasUntil) ? Week.key(until) : nil
        model.upsert(e)
        dismiss()
    }
}

import SwiftUI

/// The card for typing / editing an event.
struct EventEditor: View {
    @EnvironmentObject var model: PlannerModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: EventDraft

    private let hourOptions: [Double] = [1, 2, 3, 4, 6, 8]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type an event (optional)", text: $draft.event.title)
                        .font(.title3)
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
                    DatePicker("Starts", selection: startBinding, displayedComponents: .date)
                    Stepper(value: $draft.event.days, in: 1...60) {
                        Text(draft.event.days == 1 ? "Lasts 1 day" : "Lasts \(draft.event.days) days")
                    }
                    Stepper(value: $draft.event.lines, in: 1...Page.lines) {
                        Text(draft.event.lines == 1 ? "1 line tall" : "\(draft.event.lines) lines tall")
                    }
                    Picker("Hours (for stats)", selection: $draft.event.hrs) {
                        Text("None").tag(0.0)
                        ForEach(hourOptions, id: \.self) { h in Text("\(Int(h)) h").tag(h) }
                    }
                }
                if !draft.isNew {
                    Section {
                        Button("Delete event", role: .destructive) {
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
                    Button(draft.isNew ? "Add" : "Save") {
                        model.upsert(draft.event)
                        dismiss()
                    }
                }
            }
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { draft.event.start },
                set: { draft.event.date = Week.key($0) })
    }
}

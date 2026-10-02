import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: PlannerModel
    @State private var jumping = false
    @State private var jumpDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            if !model.fullScreen {
                topBar
                if model.screen == .planner && model.mode == .events { eventsStrip }
            }
            ZStack {
                // the book stays alive underneath so pages and ink don't reload
                BookView()
                    .padding(6)
                    .opacity(model.screen == .planner ? 1 : 0)
                    .allowsHitTesting(model.screen == .planner)
                if model.screen == .month { MonthView() }
                if model.screen == .stats { StatsView() }
            }
        }
        .background(Color(model.theme.desk).ignoresSafeArea())
        .overlay(alignment: .top) {
            if model.fullScreen {
                Button {
                    withAnimation { model.fullScreen = false }
                } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(.title2.weight(.bold))
                        .frame(width: 60, height: 26)
                        .background(Color(model.theme.chrome).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Show toolbar")
            }
        }
        .statusBarHidden(model.fullScreen)
        .persistentSystemOverlays(model.fullScreen ? .hidden : .automatic)
        .sheet(isPresented: $jumping) { jumpSheet }
        .sheet(item: $model.draft) { d in
            EventEditor(draft: d).environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            barButton("chevron.left", "Previous") { step(-1) }
            barButton("chevron.right", "Next") { step(1) }
            Button("Today") { goToday() }
                .buttonStyle(BarButtonStyle())
            if model.screen == .planner {
                barButton("calendar", "Jump to date") { jumpDate = model.weekStart; jumping = true }
            }

            Spacer(minLength: 8)
            VStack(spacing: 0) {
                Text(titleText).font(.headline)
                if model.screen == .planner { Text(model.subtitle).font(.caption).opacity(0.8) }
            }
            .lineLimit(1)
            Spacer(minLength: 8)

            Picker("Screen", selection: $model.screen) {
                ForEach(Screen.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .environment(\.colorScheme, .dark)

            if model.screen == .planner {
                Button {
                    model.mode = model.mode == .write ? .events : .write
                } label: {
                    Label(model.mode == .write ? "Write" : "Events",
                          systemImage: model.mode == .write ? "pencil.tip" : "rectangle.stack.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(BarButtonStyle(highlighted: model.mode == .events))
                .accessibilityHint("Switch between writing and adding or moving events")

                barButton("arrow.uturn.backward", "Undo") { model.commands.send(.undo) }
                barButton("arrow.uturn.forward", "Redo") { model.commands.send(.redo) }
                if model.mode == .write {
                    barButton(model.showTools ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle",
                              "Show or hide Apple Pencil tools") { model.showTools.toggle() }
                }
            }
            barButton("gearshape", "Settings") { model.showSettings = true }
            barButton("arrow.up.left.and.arrow.down.right", "Full screen") {
                withAnimation { model.fullScreen = true }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color(model.theme.chrome).ignoresSafeArea(edges: .top))
    }

    /// Category chips + how-to, shown while in Events mode.
    private var eventsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Tap a line to type · drag down over writing to tag it · drag an event to move · drag its ● to stretch days")
                    .font(.caption)
                    .foregroundStyle(Color(model.theme.muted))
                ForEach(model.categories) { c in
                    let on = c.id == model.currentCat
                    Button {
                        model.currentCat = c.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(on ? Color.white : Color(c.uiColor)).frame(width: 10, height: 10)
                            Text(c.name).font(.callout.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color(model.theme.ink))
                        .background(on ? Color(c.uiColor) : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(Color(on ? c.uiColor : model.theme.line)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(model.theme.paper))
    }

    private var titleText: String {
        switch model.screen {
        case .planner: return model.title
        case .month: return Week.monthYear(model.monthAnchor)
        case .stats: return "Where my time goes"
        }
    }

    private func step(_ n: Int) {
        switch model.screen {
        case .planner:
            model.commands.send(n > 0 ? .next : .previous)
        case .month:
            model.monthAnchor = Week.calendar.date(byAdding: .month, value: n, to: Week.monthStart(model.monthAnchor)) ?? model.monthAnchor
        case .stats:
            break
        }
    }

    private func goToday() {
        switch model.screen {
        case .planner: model.commands.send(.go(Date()))
        case .month: model.monthAnchor = Date()
        case .stats: break
        }
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 40, height: 40)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(label)
    }

    private var jumpSheet: some View {
        NavigationStack {
            DatePicker("Go to", selection: $jumpDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Jump to a week")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { jumping = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            model.commands.send(.go(jumpDate))
                            jumping = false
                        }
                    }
                }
        }
    }
}

struct BarButtonStyle: ButtonStyle {
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(minHeight: 40)
            .background(Color.white.opacity(highlighted ? 0.4 : (configuration.isPressed ? 0.3 : 0.14)),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

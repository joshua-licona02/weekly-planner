import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: PlannerModel
    @State private var choosingDate = false
    @State private var chosenDate = Date()

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
        .sheet(isPresented: $choosingDate) { dateSheet }
        .sheet(item: $model.draft) { d in
            EventEditor(draft: d).environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    // MARK: top bar
    // One row when there's room (landscape); in portrait the view switch + Write/Events
    // drop to a second row so nothing gets squeezed.

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                navButtons
                Spacer(minLength: 8)
                titleButton
                Spacer(minLength: 8)
                screenPicker
                if model.screen != .stats { modeSwitch }
                actionButtons
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    navButtons
                    Spacer(minLength: 8)
                    titleButton
                    Spacer(minLength: 8)
                    actionButtons
                }
                HStack(spacing: 12) {
                    screenPicker
                    if model.screen != .stats { modeSwitch }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color(model.theme.chrome).ignoresSafeArea(edges: .top))
    }

    @ViewBuilder private var navButtons: some View {
        barButton("chevron.left", "Previous") { step(-1) }
        barButton("chevron.right", "Next") { step(1) }
        barButton(model.screen == .month ? "book" : "calendar",
                  model.screen == .month ? "Back to planner" : "Month view") {
            model.screen = model.screen == .month ? .planner : .month
        }
    }

    /// The title is the date chooser: tap it to pick a day/month (with a Today button inside).
    private var titleButton: some View {
        Button {
            chosenDate = model.screen == .month ? model.monthAnchor : model.weekStart
            choosingDate = true
        } label: {
            HStack(spacing: 6) {
                VStack(spacing: 0) {
                    Text(titleText).font(.headline)
                    if model.screen == .planner { Text(model.subtitle).font(.caption).opacity(0.8) }
                }
                if model.screen != .stats {
                    Image(systemName: "chevron.down.circle.fill").font(.callout).opacity(0.8)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }
        .buttonStyle(BarButtonStyle())
        .fixedSize()
        .disabled(model.screen == .stats)
        .accessibilityHint("Choose a date")
    }

    private var screenPicker: some View {
        Picker("Screen", selection: $model.screen) {
            ForEach(Screen.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
        .environment(\.colorScheme, .dark)
    }

    /// Two clearly labeled halves instead of one button that flips.
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeHalf("Write", "pencil.tip", .write)
            modeHalf("Events", "rectangle.stack.badge.plus", .events)
        }
        .padding(3)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        .fixedSize()
    }

    private func modeHalf(_ title: String, _ icon: String, _ mode: InputMode) -> some View {
        let on = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .foregroundStyle(on ? Color(model.theme.chrome) : Color.white)
                .background(on ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var actionButtons: some View {
        if model.screen == .planner {
            barButton("plus", "New event") { model.beginNewTyped() }
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

    /// Category chips + how-to, shown while in Events mode.
    private var eventsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Tap a line to type an event · drag down over writing to tag it · drag an event to move it · drag its ● to stretch days")
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

    private func go(to date: Date) {
        if model.screen == .month {
            model.monthAnchor = date
        } else {
            model.commands.send(.go(date))
        }
        choosingDate = false
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 40, height: 40)
        }
        .buttonStyle(BarButtonStyle())
        .fixedSize()
        .accessibilityLabel(label)
    }

    private var dateSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Go to", selection: $chosenDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                Button {
                    go(to: Date())
                } label: {
                    Label("Today", systemImage: "calendar.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                Spacer()
            }
            .navigationTitle(model.screen == .month ? "Go to a month" : "Go to a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingDate = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Go") { go(to: chosenDate) } }
            }
        }
        .presentationDetents([.medium, .large])
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

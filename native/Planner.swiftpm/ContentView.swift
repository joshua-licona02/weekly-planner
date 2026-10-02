import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: PlannerModel
    @State private var jumping = false
    @State private var jumpDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            if !model.fullScreen {
                topBar
            }
            BookView()
                .padding(6)
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
        .sheet(isPresented: $jumping) { jumpSheet }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            barButton("chevron.left", "Previous") { model.commands.send(.previous) }
            barButton("chevron.right", "Next") { model.commands.send(.next) }
            Button("Today") { model.commands.send(.go(Date())) }
                .buttonStyle(BarButtonStyle())
            barButton("calendar", "Jump to date") { jumpDate = model.weekStart; jumping = true }

            Spacer(minLength: 8)
            VStack(spacing: 0) {
                Text(model.title).font(.headline)
                Text(model.subtitle).font(.caption).opacity(0.8)
            }
            .lineLimit(1)
            Spacer(minLength: 8)

            barButton("arrow.uturn.backward", "Undo") { model.commands.send(.undo) }
            barButton("arrow.uturn.forward", "Redo") { model.commands.send(.redo) }
            barButton(model.showTools ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle", "Show or hide Apple Pencil tools") {
                model.showTools.toggle()
            }
            Menu {
                Picker("Look", selection: $model.themeID) {
                    ForEach(PaperTheme.all) { t in Text(t.name).tag(t.id) }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            }
            .accessibilityLabel("Change look")
            barButton("arrow.up.left.and.arrow.down.right", "Full screen") {
                withAnimation { model.fullScreen = true }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color(model.theme.chrome).ignoresSafeArea(edges: .top))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(minHeight: 40)
            .background(Color.white.opacity(configuration.isPressed ? 0.3 : 0.14), in: RoundedRectangle(cornerRadius: 9))
    }
}

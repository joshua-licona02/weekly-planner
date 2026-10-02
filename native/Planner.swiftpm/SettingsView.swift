import SwiftUI
import UniformTypeIdentifiers

/// A backup file for the share/export sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject var model: PlannerModel
    @Environment(\.dismiss) private var dismiss

    private enum PickKind { case folder, backup }
    @State private var pickKind: PickKind = .backup
    @State private var picking = false
    @State private var exporting = false
    @State private var exportDoc: BackupDocument?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Look") {
                    Picker("Theme", selection: $model.themeID) {
                        ForEach(PaperTheme.all) { t in Text(t.name).tag(t.id) }
                    }
                }

                Section {
                    ForEach($model.categories) { $c in
                        HStack {
                            ColorPicker("", selection: colorBinding($c), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 44)
                            TextField("Name", text: $c.name)
                            if model.isUsed(c.id) {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                    .onDelete { model.deleteCategories(at: $0) }
                    Button("Add category") {
                        model.categories.append(EventCategory(id: UUID().uuidString, name: "New category", color: "#64748b"))
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Swipe left to delete. Categories with events (🔒) can be renamed or recolored but not deleted.")
                }

                Section {
                    LabeledContent("Saving to", value: model.storageName)
                    Button("Save in a folder (iCloud Drive)…") {
                        pickKind = .folder
                        picking = true
                    }
                    if Storage.shared.isExternal {
                        Button("Move back to this iPad only") { model.useLocalStorage() }
                    }
                } header: {
                    Text("Where it's saved")
                } footer: {
                    Text("Pick (or create) a folder in iCloud Drive and the planner saves straight into it, so iCloud backs it up and it survives app updates or a new iPad. Your existing pages are copied over.")
                }

                Section {
                    Button("Export backup…") {
                        exportDoc = BackupDocument(data: model.makeBackup())
                        exporting = true
                    }
                    Button("Import backup…") {
                        pickKind = .backup
                        picking = true
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Import also accepts a backup from the web version of the planner (its events and categories come over; web handwriting can't be converted).")
                }

                Section("Apple Pencil") {
                    Text("Double-tap / squeeze follow your iPad setting: Settings ▸ Apple Pencil. \"Switch between current tool and eraser\" gives you double-tap to erase.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: pickKind == .folder ? [.folder] : [.json],
                          allowsMultipleSelection: false) { result in
                handlePick(result)
            }
            .fileExporter(isPresented: $exporting,
                          document: exportDoc,
                          contentType: .json,
                          defaultFilename: "planner-backup-\(Week.key(Date()))") { result in
                if case .success = result { message = "Backup saved." }
            }
            .alert("Planner", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch pickKind {
        case .folder:
            message = model.useFolder(url)
        case .backup:
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                message = model.importBackup(data)
            } else {
                message = "Couldn't read that file."
            }
        }
    }

    private func colorBinding(_ c: Binding<EventCategory>) -> Binding<Color> {
        Binding(get: { Color(c.wrappedValue.uiColor) },
                set: { c.wrappedValue.color = UIColor($0).hexString })
    }
}

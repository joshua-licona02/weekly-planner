import Foundation
import PencilKit

extension Notification.Name {
    /// Pages write their ink to disk immediately when this is posted.
    static let plannerSaveAll = Notification.Name("plannerSaveAll")
}

/// Where everything is saved: the app's own storage on this iPad, or a folder you pick
/// (for example in iCloud Drive) so iCloud keeps it backed up and it survives app updates.
final class Storage {
    static let shared = Storage()

    private let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var scoped: URL?
    private(set) var folder: URL
    private let bookmarkKey = "storageFolderBookmark"

    private init() {
        folder = local
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                scoped = url
                folder = url
                if stale, let fresh = try? url.bookmarkData() {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
            }
        }
    }

    var isExternal: Bool { scoped != nil }
    var displayName: String { isExternal ? "“\(folder.lastPathComponent)” folder" : "On this iPad (app storage)" }

    // MARK: switching location

    func useFolder(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "Planner", code: 1)
        }
        let bookmark = try url.bookmarkData()
        copyPlannerFiles(from: folder, to: url)
        scoped?.stopAccessingSecurityScopedResource()
        scoped = url
        folder = url
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func useLocal() {
        guard isExternal else { return }
        copyPlannerFiles(from: folder, to: local)
        scoped?.stopAccessingSecurityScopedResource()
        scoped = nil
        folder = local
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Copies planner files that the destination doesn't already have.
    private func copyPlannerFiles(from: URL, to: URL) {
        for name in plannerFileNames(in: from) {
            let target = to.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            if let data = read(name, in: from) { write(data, name, in: to) }
        }
    }

    // MARK: file access (coordinated, so iCloud Drive files download/upload correctly)

    func read(_ name: String) -> Data? { read(name, in: folder) }
    func write(_ data: Data, _ name: String) { write(data, name, in: folder) }

    func remove(_ name: String) {
        let url = folder.appendingPathComponent(name)
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &err) { u in
            try? FileManager.default.removeItem(at: u)
        }
    }

    private func read(_ name: String, in dir: URL) -> Data? {
        let url = dir.appendingPathComponent(name)
        var result: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            result = try? Data(contentsOf: u)
        }
        return result
    }

    private func write(_ data: Data, _ name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            try? data.write(to: u, options: .atomic)
        }
    }

    func readJSON<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = read(name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func writeJSON<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) { write(data, name) }
    }

    // MARK: listing

    /// Planner file names in a folder (also recognises iCloud placeholders like ".name.icloud").
    private func plannerFileNames(in dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { raw in
            var n = raw
            if n.hasPrefix("."), n.hasSuffix(".icloud") {
                n = String(n.dropFirst().dropLast(".icloud".count))
            }
            let ours = (n.hasPrefix("ink-") && n.hasSuffix(".drawing")) || n == "events.json" || n == "categories.json"
            return ours ? n : nil
        }
    }

    /// Week keys ("2026-09-27") that have saved handwriting.
    func inkWeekKeys() -> [String] {
        plannerFileNames(in: folder)
            .filter { $0.hasPrefix("ink-") }
            .map { String($0.dropFirst(4).dropLast(".drawing".count)) }
            .sorted()
    }
}

/// One PencilKit drawing per week.
final class InkStore {
    static let shared = InkStore()

    private func name(_ week: Date) -> String { "ink-\(Week.key(week)).drawing" }

    func load(_ week: Date) -> PKDrawing {
        guard let data = Storage.shared.read(name(week)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func save(_ drawing: PKDrawing, week: Date) {
        if drawing.strokes.isEmpty {
            Storage.shared.remove(name(week))
        } else {
            Storage.shared.write(drawing.dataRepresentation(), name(week))
        }
    }
}

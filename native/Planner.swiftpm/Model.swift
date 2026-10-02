import SwiftUI
import Combine
import PencilKit

// MARK: - Page geometry (logical points, same layout as the web version)

enum Page {
    static let width: CGFloat = 1000
    static let height: CGFloat = 1400
    static let gx: CGFloat = 36          // grid left
    static let gy: CGFloat = 104         // grid top
    static let gw: CGFloat = 928         // grid width
    static let dayH: CGFloat = 160       // one day row
    static let notesH: CGFloat = 140
    static let lines = 4                 // writing lines per day
    static let lab: CGFloat = 104        // day label column
    static var lineH: CGFloat { dayH / CGFloat(lines) }
    static var right: CGFloat { gx + gw }
    static func rowY(_ i: Int) -> CGFloat { gy + CGFloat(i) * dayH }
}

// MARK: - Weeks (Sunday first)

enum Week {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }()

    static func start(of date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    static func adding(_ weeks: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: 7 * weeks, to: date) ?? date
    }

    static func day(_ i: Int, of week: Date) -> Date {
        calendar.date(byAdding: .day, value: i, to: week) ?? week
    }

    /// Whole days from a to b (b - a).
    static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    static func monthStart(_ d: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: d)) ?? d
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = format
        return f
    }
    private static let keyF = formatter("yyyy-MM-dd")
    private static let monthF = formatter("MMMM")
    private static let monShortF = formatter("MMM")
    private static let yearF = formatter("yyyy")
    private static let weekdayF = formatter("EEE")

    static func key(_ d: Date) -> String { keyF.string(from: d) }
    static func date(fromKey s: String) -> Date? { keyF.date(from: s) }
    static func weekday(_ d: Date) -> String { weekdayF.string(from: d) }
    static func monthShort(_ d: Date) -> String { monShortF.string(from: d) }
    static func monthYear(_ d: Date) -> String { "\(monthF.string(from: d)) \(yearF.string(from: d))" }

    /// "October 2026", "Sep – Oct 2026" or "Dec 2026 – Jan 2027" for the given span of days.
    static func title(_ start: Date, days: Int = 7) -> String {
        let end = day(days - 1, of: start)
        if calendar.isDate(start, equalTo: end, toGranularity: .month) { return monthYear(start) }
        if calendar.isDate(start, equalTo: end, toGranularity: .year) {
            return "\(monShortF.string(from: start)) – \(monShortF.string(from: end)) \(yearF.string(from: end))"
        }
        return "\(monShortF.string(from: start)) \(yearF.string(from: start)) – \(monShortF.string(from: end)) \(yearF.string(from: end))"
    }

    /// "Sep 27 – Oct 3"
    static func range(_ start: Date, days: Int = 7) -> String {
        let end = day(days - 1, of: start)
        return "\(monShortF.string(from: start)) \(calendar.component(.day, from: start)) – \(monShortF.string(from: end)) \(calendar.component(.day, from: end))"
    }
}

// MARK: - App state

enum Screen: String, CaseIterable, Identifiable {
    case planner = "Planner", month = "Month", stats = "Stats"
    var id: String { rawValue }
}

enum InputMode { case write, events }

enum BookCommand {
    case next, previous, go(Date), show(Date), undo, redo, reload
}

struct EventDraft: Identifiable {
    let id = UUID()
    var event: PlannerEvent
    let isNew: Bool
}

struct NativeBackup: Codable {
    var format = "weekly-planner-native"
    var version = 1
    var theme: String
    var events: [PlannerEvent]
    var categories: [EventCategory]
    var ink: [String: String]     // week key -> base64 PencilKit drawing
}

/// The web app's backup file (only its events + categories can be brought over).
struct WebBackup: Decodable {
    let format: String
    let entries: Entries
    struct Entries: Decodable {
        let events: [PlannerEvent]?
        let categories: [EventCategory]?
    }
}

final class PlannerModel: ObservableObject {
    @Published var weekStart: Date = Week.start(of: Date())
    @Published var pagesShown: Int = 1
    @Published var showTools: Bool = true
    @Published var fullScreen: Bool = false
    @Published var screen: Screen = .planner {
        didSet { if screen == .month && oldValue != .month { monthAnchor = Week.day(3, of: weekStart) } }
    }
    @Published var mode: InputMode = .write
    @Published var currentCat: String = "work"
    @Published var draft: EventDraft?
    @Published var showSettings = false
    @Published var monthAnchor: Date = Date()
    @Published var storageName: String = Storage.shared.displayName
    @Published var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: "theme") }
    }
    @Published var events: [PlannerEvent] = [] {
        didSet { if !loading { Storage.shared.writeJSON(events, "events.json") } }
    }
    @Published var categories: [EventCategory] = EventCategory.defaults {
        didSet { if !loading { Storage.shared.writeJSON(categories, "categories.json") } }
    }

    let commands = PassthroughSubject<BookCommand, Never>()
    weak var undoManager: UndoManager?
    private var loading = false

    init() {
        themeID = UserDefaults.standard.string(forKey: "theme") ?? "classic"
        reloadFromStorage()
    }

    var theme: PaperTheme { PaperTheme.all.first { $0.id == themeID } ?? PaperTheme.all[0] }
    var title: String { Week.title(weekStart, days: pagesShown * 7) }
    var subtitle: String { Week.range(weekStart, days: pagesShown * 7) }

    func reloadFromStorage() {
        loading = true
        events = Storage.shared.readJSON([PlannerEvent].self, "events.json") ?? []
        categories = Storage.shared.readJSON([EventCategory].self, "categories.json") ?? EventCategory.defaults
        if categories.isEmpty { categories = EventCategory.defaults }
        if !categories.contains(where: { $0.id == currentCat }) { currentCat = categories[0].id }
        storageName = Storage.shared.displayName
        loading = false
    }

    // MARK: categories

    func color(for cat: String) -> UIColor { categories.first { $0.id == cat }?.uiColor ?? UIColor(hex: 0x9ca3af) }
    func name(for cat: String) -> String { categories.first { $0.id == cat }?.name ?? "Other" }
    func isUsed(_ cat: String) -> Bool { events.contains { $0.cat == cat } }

    func deleteCategories(at offsets: IndexSet) {
        let removable = offsets.filter { !isUsed(categories[$0].id) }
        categories.remove(atOffsets: IndexSet(removable))
        if !categories.contains(where: { $0.id == currentCat }) { currentCat = categories.first?.id ?? "" }
    }

    // MARK: events (all changes are undoable, together with the ink)

    func beginNew(date: Date, line: Int) {
        draft = EventDraft(event: PlannerEvent(date: Week.key(date), line: line, cat: currentCat), isNew: true)
    }

    /// New event on a day, placed on the first writing line not already used by another event.
    func beginNew(date: Date) {
        let taken = expandEvents(events, from: date, to: date).flatMap { Array($0.line..<($0.line + $0.lines)) }
        let line = (0..<Page.lines).first { !taken.contains($0) } ?? 0
        beginNew(date: date, line: line)
    }

    /// "+" button: a typed event on today (if it's on screen) or the first visible day.
    func beginNewTyped() {
        let today = Week.calendar.startOfDay(for: Date())
        let visibleEnd = Week.day(pagesShown * 7 - 1, of: weekStart)
        let day = (today >= weekStart && today <= visibleEnd) ? today : weekStart
        beginNew(date: day)
    }

    /// Tapping any occurrence of a repeating event edits the whole series.
    func beginEdit(_ e: PlannerEvent) {
        let series = events.first { $0.id == e.seriesID } ?? e
        draft = EventDraft(event: series, isNew: false)
    }

    /// A drag on the page: moving/stretching one occurrence moves/stretches its whole series.
    func commitDrag(from old: PlannerEvent, to new: PlannerEvent) {
        guard var series = events.first(where: { $0.id == old.seriesID }) else { return }
        let shift = Week.days(from: old.start, to: new.start)
        series.date = Week.key(Week.day(shift, of: series.start))
        series.days = new.days
        series.line = new.line
        series.lines = new.lines
        upsert(series)
    }

    func upsert(_ e: PlannerEvent) {
        var e = e
        e.lines = min(max(e.lines, 1), Page.lines)
        e.line = min(max(e.line, 0), Page.lines - e.lines)
        e.days = min(max(e.days, 1), 60)
        let before = events.first { $0.id == e.id }
        replace(e.id, with: e)
        undoManager?.registerUndo(withTarget: self) { m in m.restore(e.id, to: before) }
    }

    func delete(_ id: String) {
        let before = events.first { $0.id == id }
        replace(id, with: nil)
        undoManager?.registerUndo(withTarget: self) { m in m.restore(id, to: before) }
    }

    private func restore(_ id: String, to e: PlannerEvent?) {
        let current = events.first { $0.id == id }
        replace(id, with: e)
        undoManager?.registerUndo(withTarget: self) { m in m.restore(id, to: current) }
    }

    private func replace(_ id: String, with e: PlannerEvent?) {
        var list = events.filter { $0.id != id }
        if let e = e { list.append(e) }
        events = list
    }

    // MARK: storage location

    func useFolder(_ url: URL) -> String {
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        do { try Storage.shared.useFolder(url) } catch { return "Couldn't use that folder. Try another one." }
        reloadFromStorage()
        commands.send(.reload)
        return "Your planner now saves to the “\(url.lastPathComponent)” folder."
    }

    func useLocalStorage() {
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        Storage.shared.useLocal()
        reloadFromStorage()
        commands.send(.reload)
    }

    // MARK: backup

    func makeBackup() -> Data {
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        var ink: [String: String] = [:]
        for key in Storage.shared.inkWeekKeys() {
            if let d = Storage.shared.read("ink-\(key).drawing") { ink[key] = d.base64EncodedString() }
        }
        let b = NativeBackup(theme: themeID, events: events, categories: categories, ink: ink)
        return (try? JSONEncoder().encode(b)) ?? Data()
    }

    func importBackup(_ data: Data) -> String {
        if let b = try? JSONDecoder().decode(NativeBackup.self, from: data), b.format == "weekly-planner-native" {
            for (k, v) in b.ink {
                if let d = Data(base64Encoded: v) { Storage.shared.write(d, "ink-\(k).drawing") }
            }
            categories = b.categories.isEmpty ? EventCategory.defaults : b.categories
            events = b.events
            themeID = b.theme
            commands.send(.reload)
            return "Backup restored: \(b.ink.count) week(s) of handwriting and \(b.events.count) event(s)."
        }
        if let w = try? JSONDecoder().decode(WebBackup.self, from: data), w.format == "weekly-planner" {
            if let cats = w.entries.categories, !cats.isEmpty {
                var merged = categories
                for c in cats where !merged.contains(where: { $0.id == c.id }) { merged.append(c) }
                categories = merged
            }
            let incoming = w.entries.events ?? []
            var list = events.filter { e in !incoming.contains(where: { $0.id == e.id }) }
            list.append(contentsOf: incoming)
            events = list
            return "Brought over \(incoming.count) event(s) from the web planner. (Handwriting from the web app can't be converted.)"
        }
        return "That file isn't a planner backup."
    }
}

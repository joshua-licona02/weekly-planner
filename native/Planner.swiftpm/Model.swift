import SwiftUI
import Combine
import PencilKit

// MARK: - Page geometry (logical points, same layout as the web version)

enum Page {
    static let width: CGFloat = 1000
    static let gx: CGFloat = 36          // grid left
    static let gy: CGFloat = 104         // grid top
    static let gw: CGFloat = 928         // grid width
    static let dayH: CGFloat = 160       // one day row (before any added lines)
    static let notesH: CGFloat = 140
    static let lines = 4                 // writing lines per day (before any added lines)
    static let maxExtraLines = 12        // most lines the + button can add to one day
    static let lab: CGFloat = 104        // day label column
    static var lineH: CGFloat { dayH / CGFloat(lines) }
    static var right: CGFloat { gx + gw }
}

/// Where the day rows sit on one week's page. Days can have extra lines (the + button),
/// which makes that row taller and pushes everything below it down.
struct WeekLayout: Equatable {
    var lines: [Int]                     // writing lines for each of the 7 days

    static let standard = WeekLayout(lines: Array(repeating: Page.lines, count: 7))

    func rowH(_ i: Int) -> CGFloat { CGFloat(lines[i]) * Page.lineH }
    /// Top of day row i (i = 7 is the notes box).
    func rowY(_ i: Int) -> CGFloat { Page.gy + (0..<min(max(i, 0), 7)).reduce(CGFloat(0)) { $0 + rowH($1) } }
    var notesY: CGFloat { rowY(7) }
    var height: CGFloat { notesY + Page.notesH + 36 }

    /// The day row containing y: -1 above the grid, 7 in/below the notes box.
    func row(at y: CGFloat) -> Int {
        if y < Page.gy { return -1 }
        return (0..<7).first { y < rowY($0 + 1) } ?? 7
    }

    /// The writing area of one day row.
    func dayRect(_ i: Int) -> CGRect {
        CGRect(x: Page.gx + Page.lab, y: rowY(i), width: Page.right - (Page.gx + Page.lab), height: rowH(i))
    }

    /// The + / − buttons at the bottom of a day's label column.
    func addRect(_ i: Int) -> CGRect { CGRect(x: Page.gx + 10, y: rowY(i) + rowH(i) - 34, width: 28, height: 28) }
    func removeRect(_ i: Int) -> CGRect { addRect(i).offsetBy(dx: 36, dy: 0) }
    func canAdd(_ i: Int) -> Bool { lines[i] < Page.lines + Page.maxExtraLines }
    func canRemove(_ i: Int) -> Bool { lines[i] > Page.lines }

    /// How far ink at height y (laid out with `old`) moves to stay on the same day in this layout.
    func offset(forY y: CGFloat, from old: WeekLayout) -> CGFloat {
        let r = old.row(at: y)
        if r < 0 { return 0 }
        return rowY(r) - old.rowY(r)
    }
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
    case planner = "Planner", month = "Month", notes = "Notes", stats = "Stats"
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
    var notes: String?            // base64 PencilKit drawing of the Notes page
    var dayLines: [String: Int]?  // day key -> lines added with the + button
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
        didSet {
            if screen != .planner { NotificationCenter.default.post(name: .plannerSaveAll, object: nil) }
            if screen == .month && oldValue != .month { monthAnchor = Week.day(3, of: weekStart) }
        }
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
    /// Lines added to a day with its + button (day key -> extra lines).
    @Published var extraLines: [String: Int] = [:] {
        didSet { if !loading { Storage.shared.writeJSON(extraLines, DayLines.fileName) } }
    }
    @Published var showFederalHolidays: Bool {
        didSet { UserDefaults.standard.set(showFederalHolidays, forKey: "holidaysFederal") }
    }
    @Published var showObservances: Bool {
        didSet { UserDefaults.standard.set(showObservances, forKey: "holidaysObservances") }
    }
    /// Goes up whenever everything was re-read from storage (so the Notes page reloads too).
    @Published private(set) var storageGeneration = 0
    /// A message shown in an alert over the planner.
    @Published var notice: String?

    let commands = PassthroughSubject<BookCommand, Never>()
    weak var undoManager: UndoManager?
    private var loading = false

    init() {
        themeID = UserDefaults.standard.string(forKey: "theme") ?? "classic"
        showFederalHolidays = UserDefaults.standard.object(forKey: "holidaysFederal") as? Bool ?? true
        showObservances = UserDefaults.standard.object(forKey: "holidaysObservances") as? Bool ?? true
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
        extraLines = Storage.shared.readJSON([String: Int].self, DayLines.fileName) ?? [:]
        storageName = Storage.shared.displayName
        loading = false
        storageGeneration += 1
    }

    // MARK: holidays

    func holidays(on day: Date) -> [Holiday] {
        Holidays.on(day).filter { $0.federal ? showFederalHolidays : showObservances }
    }

    // MARK: day lines (the + / − buttons on each day)

    func layout(for week: Date) -> WeekLayout {
        WeekLayout(lines: (0..<7).map { lines(on: Week.day($0, of: week)) })
    }

    func lines(on day: Date) -> Int { Page.lines + (extraLines[Week.key(day)] ?? 0) }

    func addLine(_ day: Date) {
        let extra = extraLines[Week.key(day)] ?? 0
        guard extra < Page.maxExtraLines else { return }
        setExtraLines(day, extra + 1)
    }

    /// Takes away the last added line, as long as nothing is written on it.
    func removeLine(_ day: Date) {
        let extra = extraLines[Week.key(day)] ?? 0
        guard extra > 0 else { return }
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        let week = Week.start(of: day)
        let lay = layout(for: week)
        let row = Week.days(from: week, to: day)
        let lastLine = CGRect(x: 0, y: lay.rowY(row + 1) - Page.lineH, width: Page.width, height: Page.lineH)
        let used = InkStore.shared.load(week).strokes.contains {
            lastLine.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY))
        }
        if used {
            notice = "There's writing on the last line of that day. Erase it first, then tap − again."
            return
        }
        setExtraLines(day, extra - 1)
    }

    /// Changes a day's line count and moves the week's handwriting so it stays on its day (undoable).
    private func setExtraLines(_ day: Date, _ n: Int) {
        NotificationCenter.default.post(name: .plannerSaveAll, object: nil)
        let week = Week.start(of: day)
        let key = Week.key(day)
        let before = extraLines[key] ?? 0
        let old = layout(for: week)
        var map = extraLines
        if n > 0 { map[key] = n } else { map.removeValue(forKey: key) }
        extraLines = map
        InkStore.shared.relayout(week: week, from: old, to: layout(for: week))
        NotificationCenter.default.post(name: .plannerInkChangedElsewhere, object: Week.key(week))
        undoManager?.registerUndo(withTarget: self) { m in m.setExtraLines(day, before) }
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
        let line = (0..<lines(on: date)).first { !taken.contains($0) } ?? 0
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
        e.line = min(max(e.line, 0), max(lines(on: e.start) - e.lines, 0))
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
        let notes = Storage.shared.read(NotesStore.fileName)?.base64EncodedString()
        let b = NativeBackup(theme: themeID, events: events, categories: categories, ink: ink,
                             notes: notes, dayLines: extraLines)
        return (try? JSONEncoder().encode(b)) ?? Data()
    }

    func importBackup(_ data: Data) -> String {
        if let b = try? JSONDecoder().decode(NativeBackup.self, from: data), b.format == "weekly-planner-native" {
            for (k, v) in b.ink {
                if let d = Data(base64Encoded: v) { Storage.shared.write(d, "ink-\(k).drawing") }
            }
            if let n = b.notes, let d = Data(base64Encoded: n) { Storage.shared.write(d, NotesStore.fileName) }
            categories = b.categories.isEmpty ? EventCategory.defaults : b.categories
            events = b.events
            if let l = b.dayLines { extraLines = l }
            themeID = b.theme
            storageGeneration += 1
            commands.send(.reload)
            return "Backup restored: \(b.ink.count) week(s) of handwriting, your notes and \(b.events.count) event(s)."
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

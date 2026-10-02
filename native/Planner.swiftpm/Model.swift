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
    static func weekday(_ d: Date) -> String { weekdayF.string(from: d) }
    static func monthShort(_ d: Date) -> String { monShortF.string(from: d) }

    /// "October 2026", "Sep – Oct 2026" or "Dec 2026 – Jan 2027" for the given span of days.
    static func title(_ start: Date, days: Int = 7) -> String {
        let end = day(days - 1, of: start)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
        if sameMonth { return "\(monthF.string(from: start)) \(yearF.string(from: start))" }
        if sameYear { return "\(monShortF.string(from: start)) – \(monShortF.string(from: end)) \(yearF.string(from: end))" }
        return "\(monShortF.string(from: start)) \(yearF.string(from: start)) – \(monShortF.string(from: end)) \(yearF.string(from: end))"
    }

    /// "Sep 27 – Oct 3"
    static func range(_ start: Date, days: Int = 7) -> String {
        let end = day(days - 1, of: start)
        let c = calendar
        return "\(monShortF.string(from: start)) \(c.component(.day, from: start)) – \(monShortF.string(from: end)) \(c.component(.day, from: end))"
    }
}

// MARK: - Ink storage (one PencilKit drawing per week, in the app's Documents folder)

final class InkStore {
    static let shared = InkStore()
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private func url(_ week: Date) -> URL {
        dir.appendingPathComponent("ink-\(Week.key(week)).drawing")
    }

    func load(_ week: Date) -> PKDrawing {
        guard let data = try? Data(contentsOf: url(week)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func save(_ drawing: PKDrawing, week: Date) {
        let target = url(week)
        if drawing.strokes.isEmpty {
            try? FileManager.default.removeItem(at: target)
        } else {
            try? drawing.dataRepresentation().write(to: target, options: .atomic)
        }
    }
}

// MARK: - App state

enum BookCommand {
    case next, previous, go(Date), undo, redo
}

final class PlannerModel: ObservableObject {
    @Published var weekStart: Date = Week.start(of: Date())
    @Published var pagesShown: Int = 1
    @Published var showTools: Bool = true
    @Published var fullScreen: Bool = false
    @Published var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: "theme") }
    }

    let commands = PassthroughSubject<BookCommand, Never>()

    init() {
        themeID = UserDefaults.standard.string(forKey: "theme") ?? "classic"
    }

    var theme: PaperTheme { PaperTheme.all.first { $0.id == themeID } ?? PaperTheme.all[0] }

    var title: String { Week.title(weekStart, days: pagesShown * 7) }
    var subtitle: String { Week.range(weekStart, days: pagesShown * 7) }
}

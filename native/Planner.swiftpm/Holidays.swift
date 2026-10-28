import Foundation

struct Holiday: Hashable {
    let name: String
    let federal: Bool       // US federal holiday (otherwise a popular observance)
}

/// US federal holidays and popular observances, worked out on the iPad (nothing is downloaded).
enum Holidays {
    private static var cache: [Int: [String: [Holiday]]] = [:]
    private static var cal: Calendar { Week.calendar }

    /// Everything that falls on this day (federal first).
    static func on(_ date: Date) -> [Holiday] {
        forYear(cal.component(.year, from: date))[Week.key(date)] ?? []
    }

    private static func forYear(_ year: Int) -> [String: [Holiday]] {
        if let c = cache[year] { return c }
        var out: [String: [Holiday]] = [:]

        func add(_ d: Date?, _ name: String, federal: Bool) {
            guard let d = d, cal.component(.year, from: d) == year else { return }
            out[Week.key(d), default: []].append(Holiday(name: name, federal: federal))
        }
        // fixed-date federal holidays are observed on the Friday/Monday when they land on a weekend
        func fixed(_ y: Int, _ m: Int, _ d: Int, _ name: String) {
            guard let day = date(y, m, d) else { return }
            add(day, name, federal: true)
            switch cal.component(.weekday, from: day) {
            case 7: add(cal.date(byAdding: .day, value: -1, to: day), "\(name) (observed)", federal: true)
            case 1: add(cal.date(byAdding: .day, value: 1, to: day), "\(name) (observed)", federal: true)
            default: break
            }
        }

        // federal (weekday: 1 = Sunday, 2 = Monday ... 5 = Thursday)
        fixed(year, 1, 1, "New Year's Day")
        fixed(year + 1, 1, 1, "New Year's Day")     // observed on Dec 31 when Jan 1 is a Saturday
        add(nth(3, 2, 1, year), "Martin Luther King Jr. Day", federal: true)
        add(nth(3, 2, 2, year), "Presidents' Day", federal: true)
        add(last(2, 5, year), "Memorial Day", federal: true)
        if year >= 2021 { fixed(year, 6, 19, "Juneteenth") }
        fixed(year, 7, 4, "Independence Day")
        add(nth(1, 2, 9, year), "Labor Day", federal: true)
        add(nth(2, 2, 10, year), "Columbus Day", federal: true)
        fixed(year, 11, 11, "Veterans Day")
        add(nth(4, 5, 11, year), "Thanksgiving", federal: true)
        fixed(year, 12, 25, "Christmas Day")

        // popular observances
        let easter = easterSunday(year)
        add(date(year, 2, 14), "Valentine's Day", federal: false)
        add(nth(2, 1, 3, year), "Daylight Saving Time begins", federal: false)
        add(date(year, 3, 17), "St. Patrick's Day", federal: false)
        add(easter.flatMap { cal.date(byAdding: .day, value: -46, to: $0) }, "Ash Wednesday", federal: false)
        add(easter.flatMap { cal.date(byAdding: .day, value: -7, to: $0) }, "Palm Sunday", federal: false)
        add(easter.flatMap { cal.date(byAdding: .day, value: -2, to: $0) }, "Good Friday", federal: false)
        add(easter, "Easter", federal: false)
        add(nth(2, 1, 5, year), "Mother's Day", federal: false)
        add(nth(3, 1, 6, year), "Father's Day", federal: false)
        add(date(year, 10, 31), "Halloween", federal: false)
        add(nth(1, 1, 11, year), "Daylight Saving Time ends", federal: false)
        add(date(year, 12, 24), "Christmas Eve", federal: false)
        add(date(year, 12, 31), "New Year's Eve", federal: false)

        for (k, list) in out { out[k] = list.sorted { $0.federal && !$1.federal } }
        cache[year] = out
        return out
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        cal.date(from: DateComponents(year: y, month: m, day: d))
    }

    /// The nth given weekday of a month (e.g. 4th Thursday of November).
    private static func nth(_ n: Int, _ weekday: Int, _ month: Int, _ year: Int) -> Date? {
        guard let first = date(year, month, 1) else { return nil }
        let offset = (weekday - cal.component(.weekday, from: first) + 7) % 7 + (n - 1) * 7
        return cal.date(byAdding: .day, value: offset, to: first)
    }

    /// The last given weekday of a month (e.g. last Monday of May).
    private static func last(_ weekday: Int, _ month: Int, _ year: Int) -> Date? {
        guard let first = date(year, month, 1),
              let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return nil }
        let back = (cal.component(.weekday, from: end) - weekday + 7) % 7
        return cal.date(byAdding: .day, value: -back, to: end)
    }

    /// Western (Gregorian) Easter Sunday.
    private static func easterSunday(_ y: Int) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return date(y, month, day)
    }
}

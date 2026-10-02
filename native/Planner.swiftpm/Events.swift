import UIKit

/// Same core shape as the web app's events (so web backups can be imported), plus times and repeats.
struct PlannerEvent: Codable, Identifiable, Equatable {
    var id: String
    var date: String        // start day, "yyyy-MM-dd"
    var days: Int
    var line: Int           // first writing line it sits on (0...3)
    var lines: Int          // how many lines tall
    var cat: String
    var title: String
    var hrs: Double         // hours, for stats (set automatically for timed events)
    var startMin: Int?      // minutes after midnight; nil = all day
    var endMin: Int?
    var repeatRule: String  // "none", "daily", "weekly", "biweekly", "monthly", "yearly"
    var until: String?      // last day a repeat may start, "yyyy-MM-dd"

    init(id: String = UUID().uuidString, date: String, days: Int = 1, line: Int = 0, lines: Int = 1,
         cat: String, title: String = "", hrs: Double = 0) {
        self.id = id; self.date = date; self.days = days; self.line = line
        self.lines = lines; self.cat = cat; self.title = title; self.hrs = hrs
        self.startMin = nil; self.endMin = nil; self.repeatRule = "none"; self.until = nil
    }

    // tolerant decoding: older/web files may leave fields out
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        days = max(1, (try? c.decode(Int.self, forKey: .days)) ?? 1)
        line = (try? c.decode(Int.self, forKey: .line)) ?? 0
        lines = max(1, (try? c.decode(Int.self, forKey: .lines)) ?? 1)
        cat = (try? c.decode(String.self, forKey: .cat)) ?? "work"
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        hrs = (try? c.decode(Double.self, forKey: .hrs)) ?? 0
        startMin = try? c.decode(Int.self, forKey: .startMin)
        endMin = try? c.decode(Int.self, forKey: .endMin)
        repeatRule = (try? c.decode(String.self, forKey: .repeatRule)) ?? "none"
        until = try? c.decode(String.self, forKey: .until)
    }

    var start: Date { Week.date(fromKey: date) ?? Week.calendar.startOfDay(for: Date()) }
    var end: Date { Week.day(days - 1, of: start) }
    var repeats: Bool { repeatRule != "none" }

    /// Occurrences of a repeating event are copies with ids like "<series id>#2026-10-04".
    var seriesID: String { id.components(separatedBy: "#").first ?? id }

    /// "9:00 AM" for timed events.
    var timeLabel: String? {
        guard let m = startMin else { return nil }
        let h = (m / 60) % 24, mm = m % 60
        return String(format: "%d:%02d %@", h % 12 == 0 ? 12 : h % 12, mm, h < 12 ? "AM" : "PM")
    }

    /// Text shown on the page and in Month view.
    func label(categoryName: String) -> String {
        let base = title.isEmpty ? categoryName : title
        if let t = timeLabel { return "\(t)  \(base)" }
        return base
    }

    private func startOfOccurrence(_ k: Int) -> Date? {
        let cal = Week.calendar
        switch repeatRule {
        case "daily": return cal.date(byAdding: .day, value: k, to: start)
        case "weekly": return cal.date(byAdding: .day, value: 7 * k, to: start)
        case "biweekly": return cal.date(byAdding: .day, value: 14 * k, to: start)
        case "monthly": return cal.date(byAdding: .month, value: k, to: start)
        case "yearly": return cal.date(byAdding: .year, value: k, to: start)
        default: return k == 0 ? start : nil
        }
    }

    /// Every occurrence that overlaps from...to (just itself if it doesn't repeat).
    func occurrences(from: Date, to: Date) -> [PlannerEvent] {
        guard repeats else { return (start <= to && end >= from) ? [self] : [] }
        let limit = until.flatMap { Week.date(fromKey: $0) }
        let step: Int? = ["daily": 1, "weekly": 7, "biweekly": 14][repeatRule]
        var k = 0
        if let step = step {                       // jump straight to the first useful occurrence
            k = max(0, (Week.days(from: start, to: from) - days + 1) / step)
        }
        var out: [PlannerEvent] = []
        var guardCount = 0
        while guardCount < 800, let s = startOfOccurrence(k) {
            guardCount += 1
            if s > to { break }
            if let u = limit, s > u { break }
            if Week.day(days - 1, of: s) >= from {
                var c = self
                c.id = "\(id)#\(Week.key(s))"
                c.date = Week.key(s)
                out.append(c)
            }
            k += 1
        }
        return out
    }
}

struct RepeatRule: Identifiable {
    let id: String
    let name: String

    static let options: [RepeatRule] = [
        RepeatRule(id: "none", name: "Never"), RepeatRule(id: "daily", name: "Every day"),
        RepeatRule(id: "weekly", name: "Every week"), RepeatRule(id: "biweekly", name: "Every 2 weeks"),
        RepeatRule(id: "monthly", name: "Every month"), RepeatRule(id: "yearly", name: "Every year")
    ]
}

/// All events (with repeats expanded) that overlap from...to.
func expandEvents(_ events: [PlannerEvent], from: Date, to: Date) -> [PlannerEvent] {
    events.flatMap { $0.occurrences(from: from, to: to) }
}

struct EventCategory: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String       // "#rrggbb"

    var uiColor: UIColor { UIColor(hexString: color) }

    static let defaults: [EventCategory] = [
        EventCategory(id: "work", name: "Work", color: "#3b82f6"),
        EventCategory(id: "family", name: "Family", color: "#ec4899"),
        EventCategory(id: "health", name: "Health & Fitness", color: "#22c55e"),
        EventCategory(id: "faith", name: "Church & Faith", color: "#8b5cf6"),
        EventCategory(id: "social", name: "Social", color: "#f59e0b"),
        EventCategory(id: "errands", name: "Errands", color: "#14b8a6"),
        EventCategory(id: "study", name: "School / Study", color: "#ef4444"),
        EventCategory(id: "hobby", name: "Hobbies", color: "#f97316")
    ]
}

extension UIColor {
    convenience init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        self.init(hex: UInt32(s, radix: 16) ?? 0x9ca3af)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

// MARK: - Where events sit on a week page (shared by drawing and touch handling)

struct EventGeo {
    let event: PlannerEvent
    let lane: CGRect          // the colored bar in the lane column (spans all its days)
    let bands: [CGRect]       // one tinted band per day it covers
    let startsHere: Bool
    let endsHere: Bool
    let grip: CGPoint?        // the ● you drag to stretch it (on the page where it ends)
}

struct EventHit {
    let geo: EventGeo
    let grip: Bool
}

enum EventLayout {
    static let lanes = 3
    static let laneW: CGFloat = 14
    static var writeX: CGFloat { Page.gx + Page.lab + CGFloat(lanes) * laneW + 6 }

    static func geometry(week: Date, events: [PlannerEvent], preview: PlannerEvent? = nil) -> [EventGeo] {
        var all = expandEvents(events, from: week, to: Week.day(6, of: week))
        if let p = preview {
            if let i = all.firstIndex(where: { $0.id == p.id }) { all[i] = p } else { all.append(p) }
        }
        let list = all
            .filter { e in
                let off = Week.days(from: week, to: e.start)
                return off <= 6 && off + e.days - 1 >= 0
            }
            .sorted { a, b in a.date == b.date ? a.days > b.days : a.date < b.date }

        var laneEnd = Array(repeating: -1, count: lanes)
        var out: [EventGeo] = []
        for e in list {
            let off = Week.days(from: week, to: e.start)
            let si = max(0, off), ei = min(6, off + e.days - 1)
            let lane = laneEnd.firstIndex(where: { $0 < si }) ?? (lanes - 1)
            laneEnd[lane] = max(laneEnd[lane], ei)
            let startsHere = off >= 0
            let endsHere = off + e.days - 1 <= 6
            let lineTop = CGFloat(e.line) * Page.lineH
            let top = startsHere ? Page.rowY(si) + lineTop + 3 : Page.rowY(0)
            let bottom = endsHere ? Page.rowY(ei) + CGFloat(e.line + e.lines) * Page.lineH - 3 : Page.rowY(6) + Page.dayH
            let lx = Page.gx + Page.lab + CGFloat(lane) * laneW + 2
            let lw = laneW - 4
            var bands: [CGRect] = []
            for d in si...ei {
                bands.append(CGRect(x: writeX, y: Page.rowY(d) + lineTop, width: Page.right - writeX, height: CGFloat(e.lines) * Page.lineH))
            }
            out.append(EventGeo(event: e,
                                lane: CGRect(x: lx, y: top, width: lw, height: max(bottom - top, 10)),
                                bands: bands,
                                startsHere: startsHere,
                                endsHere: endsHere,
                                grip: endsHere ? CGPoint(x: lx + lw / 2, y: bottom) : nil))
        }
        return out
    }

    static func hit(_ p: CGPoint, in geo: [EventGeo]) -> EventHit? {
        for g in geo {
            if let grip = g.grip, hypot(p.x - grip.x, p.y - grip.y) < 26 { return EventHit(geo: g, grip: true) }
        }
        for g in geo.reversed() {
            if g.lane.insetBy(dx: -6, dy: 0).contains(p) { return EventHit(geo: g, grip: false) }
            if g.bands.contains(where: { $0.contains(p) }) { return EventHit(geo: g, grip: false) }
        }
        return nil
    }
}

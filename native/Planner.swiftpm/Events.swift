import UIKit

/// Same shape as the web app's events, so web backups can be imported.
struct PlannerEvent: Codable, Identifiable, Equatable {
    var id: String
    var date: String        // start day, "yyyy-MM-dd"
    var days: Int
    var line: Int           // first writing line it sits on (0...3)
    var lines: Int          // how many lines tall
    var cat: String
    var title: String
    var hrs: Double         // optional hours, for stats

    init(id: String = UUID().uuidString, date: String, days: Int = 1, line: Int = 0, lines: Int = 1,
         cat: String, title: String = "", hrs: Double = 0) {
        self.id = id; self.date = date; self.days = days; self.line = line
        self.lines = lines; self.cat = cat; self.title = title; self.hrs = hrs
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
    }

    var start: Date { Week.date(fromKey: date) ?? Week.calendar.startOfDay(for: Date()) }
    var end: Date { Week.day(days - 1, of: start) }
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

    static func geometry(week: Date, events: [PlannerEvent]) -> [EventGeo] {
        let list = events
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

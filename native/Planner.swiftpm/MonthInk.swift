import SwiftUI
import PencilKit

extension Notification.Name {
    /// Posted with the week key (String) when a week's ink was changed from Month view.
    static let plannerInkChangedElsewhere = Notification.Name("plannerInkChangedElsewhere")
    /// Posted with the week key (String) whenever a week's ink is written to disk.
    static let plannerInkSaved = Notification.Name("plannerInkSaved")
}

/// The writing area of one day row on a weekly page, in page coordinates.
func dayRowRect(_ index: Int) -> CGRect {
    CGRect(x: Page.gx + Page.lab, y: Page.rowY(index), width: Page.right - (Page.gx + Page.lab), height: Page.dayH)
}

private func strokes(in d: PKDrawing, row: Int) -> [PKStroke] {
    let rect = dayRowRect(row)
    return d.strokes.filter { rect.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY)) }
}

/// Month view's handwriting: per-day miniatures rendered in the background and cached
/// (so the month opens instantly), and ink written in Month view placed onto the planner.
final class MonthInk: ObservableObject {
    @Published private(set) var version = 0
    private var images: [String: (UIImage, CGRect)] = [:]   // "<day key>|d/l"
    private var ready = Set<String>()                         // "<week key>|d/l" rendered
    private var inFlight = Set<String>()
    private let queue = DispatchQueue(label: "planner.month-ink", qos: .userInitiated)
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .plannerInkSaved, object: nil, queue: .main) { [weak self] n in
            if let key = n.object as? String { self?.invalidate(weekKey: key) }
        }
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    /// Cached miniature for a day (nil if nothing written or not rendered yet).
    func miniature(for day: Date, dark: Bool) -> (UIImage, CGRect)? {
        images[Week.key(day) + (dark ? "|d" : "|l")]
    }

    private func invalidate(weekKey: String) {
        ready = ready.filter { !$0.hasPrefix(weekKey) }
        guard let week = Week.date(fromKey: weekKey) else { return }
        for i in 0..<7 {
            let k = Week.key(Week.day(i, of: week))
            images[k + "|d"] = nil
            images[k + "|l"] = nil
        }
    }

    /// Render miniatures for these weeks in the background; the view refreshes when they're ready.
    func prepare(weeks: [Date], dark: Bool, scale: CGFloat) {
        let mode = dark ? "|d" : "|l"
        let todo = weeks.filter { w in
            let k = Week.key(w) + mode
            return !ready.contains(k) && !inFlight.contains(k)
        }
        guard !todo.isEmpty else { return }
        todo.forEach { inFlight.insert(Week.key($0) + mode) }

        queue.async { [weak self] in
            var rendered: [String: (UIImage, CGRect)] = [:]
            for week in todo {
                let drawing = InkStore.shared.load(week)
                for row in 0..<7 {
                    let list = strokes(in: drawing, row: row)
                    guard !list.isEmpty else { continue }
                    let bounds = list.reduce(CGRect.null) { $0.union($1.renderBounds) }.insetBy(dx: -4, dy: -4)
                    var image = UIImage()
                    UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
                        image = PKDrawing(strokes: list).image(from: bounds, scale: scale)
                    }
                    rendered[Week.key(Week.day(row, of: week)) + mode] = (image, bounds)
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (k, v) in rendered { self.images[k] = v }
                for week in todo {
                    let k = Week.key(week) + mode
                    self.inFlight.remove(k)
                    self.ready.insert(k)
                }
                self.version += 1
            }
        }
    }

    /// Strokes written over a day box (in box coordinates, box size `cellSize`) go into that
    /// day's row on the weekly page, scaled up, placed after anything already written there.
    func add(_ newStrokes: [PKStroke], cellOrigin: CGPoint, cellSize: CGSize, day: Date, shift: inout CGFloat?) {
        let week = Week.start(of: day)
        let row = Week.days(from: week, to: day)
        var d = InkStore.shared.load(week)          // always fresh from disk
        let rowRect = dayRowRect(row)
        let x0 = EventLayout.writeX
        let s = Page.dayH / max(cellSize.height, 1)

        if shift == nil {
            let rightmost = strokes(in: d, row: row).map { $0.renderBounds.maxX }.max() ?? 0
            var sh = rightmost > x0 ? rightmost - x0 + 24 : 0
            if x0 + sh + cellSize.width * s > rowRect.maxX { sh = 0 }   // no room left: write over the start
            shift = sh
        }
        let map = CGAffineTransform(translationX: -cellOrigin.x, y: -cellOrigin.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: x0 + (shift ?? 0), y: rowRect.minY))

        for var stroke in newStrokes {
            stroke.transform = stroke.transform.concatenating(map)
            d.strokes.append(stroke)
        }
        InkStore.shared.save(d, week: week)        // also invalidates this week's miniatures
        NotificationCenter.default.post(name: .plannerInkChangedElsewhere, object: Week.key(week))
    }
}

/// Transparent writing layer over the month grid. The Pencil writes; finger taps and
/// swipes are handed back to Month view (to open days/events or change month).
struct MonthInkCanvas: UIViewRepresentable {
    let gridStart: Date
    let weeks: Int
    let dark: Bool
    let ink: MonthInk
    let onTap: (CGPoint, CGSize) -> Void
    let onSwipe: (Int) -> Void
    let onCommitted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let c = PKCanvasView()
        c.backgroundColor = .clear
        c.isOpaque = false
        c.drawingPolicy = .pencilOnly
        c.isScrollEnabled = false
        c.tool = PKInkingTool(.pen, color: .black, width: 2.2)
        c.delegate = context.coordinator

        let finger = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.allowedTouchTypes = finger
        c.addGestureRecognizer(tap)
        for dir in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
            swipe.direction = dir
            swipe.allowedTouchTypes = finger
            c.addGestureRecognizer(swipe)
        }
        return c
    }

    func updateUIView(_ c: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        c.overrideUserInterfaceStyle = dark ? .dark : .light
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: MonthInkCanvas?
        private var pending: DispatchWorkItem?
        private var clearing = false
        private var shifts: [String: CGFloat?] = [:]   // one placement per day while you write

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            parent?.onTap(g.location(in: v), v.bounds.size)
        }

        @objc func swiped(_ g: UISwipeGestureRecognizer) {
            parent?.onSwipe(g.direction == .left ? 1 : -1)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !clearing else { return }
            pending?.cancel()
            // wait until you pause, so a whole word moves over together
            let work = DispatchWorkItem { [weak self, weak canvasView] in
                guard let self = self, let canvasView = canvasView else { return }
                self.commit(canvasView)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        }

        private func commit(_ canvas: PKCanvasView) {
            guard let p = parent, !canvas.drawing.strokes.isEmpty else { return }
            let size = canvas.bounds.size
            let cellW = size.width / 7
            let cellH = size.height / CGFloat(max(p.weeks, 1))
            var byDay: [Int: [PKStroke]] = [:]
            for s in canvas.drawing.strokes {
                let c = CGPoint(x: s.renderBounds.midX, y: s.renderBounds.midY)
                let col = min(max(Int(c.x / cellW), 0), 6)
                let row = min(max(Int(c.y / cellH), 0), p.weeks - 1)
                byDay[row * 7 + col, default: []].append(s)
            }
            for (index, list) in byDay {
                let row = index / 7, col = index % 7
                let day = Week.day(row * 7 + col, of: p.gridStart)
                let key = Week.key(day)
                var shift: CGFloat? = shifts[key] ?? nil
                p.ink.add(list, cellOrigin: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH),
                          cellSize: CGSize(width: cellW, height: cellH), day: day, shift: &shift)
                shifts[key] = shift
            }
            p.onCommitted()
            // keep the ink on screen until its miniature has been drawn, then remove just
            // those strokes (anything you started writing meanwhile stays)
            let committed = canvas.drawing.strokes.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak canvas] in
                guard let self = self, let canvas = canvas else { return }
                let rest = Array(canvas.drawing.strokes.dropFirst(committed))
                self.clearing = true
                canvas.drawing = PKDrawing(strokes: rest)
                self.clearing = false
                if !rest.isEmpty { self.canvasViewDrawingDidChange(canvas) }
            }
        }
    }
}

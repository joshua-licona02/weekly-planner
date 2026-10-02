import SwiftUI
import PencilKit

extension Notification.Name {
    /// Posted with the week key (String) when a week's ink was changed from Month view.
    static let plannerInkChangedElsewhere = Notification.Name("plannerInkChangedElsewhere")
}

/// The writing area of one day row on a weekly page, in page coordinates.
func dayRowRect(_ index: Int) -> CGRect {
    CGRect(x: Page.gx + Page.lab, y: Page.rowY(index), width: Page.right - (Page.gx + Page.lab), height: Page.dayH)
}

/// Loads the weekly handwriting for Month view, makes per-day miniatures, and writes
/// ink done in Month view back into the right day row of the right weekly page.
final class MonthInk: ObservableObject {
    @Published private(set) var version = 0
    private var drawings: [String: PKDrawing] = [:]
    private var images: [String: (UIImage, CGRect)] = [:]

    func reset() {
        drawings.removeAll()
        images.removeAll()
        version += 1
    }

    private func drawing(for week: Date) -> PKDrawing {
        let key = Week.key(week)
        if let d = drawings[key] { return d }
        let d = InkStore.shared.load(week)
        drawings[key] = d
        return d
    }

    private func strokes(in d: PKDrawing, row: Int) -> [PKStroke] {
        let rect = dayRowRect(row)
        return d.strokes.filter { rect.contains(CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY)) }
    }

    /// A miniature of what's written on that day, plus the page-space rect it covers.
    func miniature(for day: Date, dark: Bool) -> (UIImage, CGRect)? {
        let key = Week.key(day) + (dark ? "d" : "l")
        if let hit = images[key] { return hit }
        let week = Week.start(of: day)
        let row = Week.days(from: week, to: day)
        let list = strokes(in: drawing(for: week), row: row)
        guard !list.isEmpty else { return nil }
        let bounds = list.reduce(CGRect.null) { $0.union($1.renderBounds) }.insetBy(dx: -4, dy: -4)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = PKDrawing(strokes: list).image(from: bounds, scale: UIScreen.main.scale)
        }
        images[key] = (image, bounds)
        return (image, bounds)
    }

    /// Strokes written over a day box (in box coordinates, box size `cell`) go into that
    /// day's row on the weekly page, scaled up, placed after anything already written there.
    func add(_ newStrokes: [PKStroke], cellOrigin: CGPoint, cellSize: CGSize, day: Date, shift: inout CGFloat?) {
        let week = Week.start(of: day)
        let row = Week.days(from: week, to: day)
        var d = drawing(for: week)
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
        drawings[Week.key(week)] = d
        images = images.filter { !$0.key.hasPrefix(Week.key(day)) }
        InkStore.shared.save(d, week: week)
        NotificationCenter.default.post(name: .plannerInkChangedElsewhere, object: Week.key(week))
        version += 1
    }
}

/// A PencilKit canvas that only claims Apple Pencil touches, so fingers still reach
/// the days and event bars underneath.
final class PencilOnlyCanvas: PKCanvasView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let touches = event?.allTouches, touches.contains(where: { $0.type == .pencil }) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Transparent writing layer over the month grid.
struct MonthInkCanvas: UIViewRepresentable {
    let gridStart: Date
    let weeks: Int
    let enabled: Bool
    let dark: Bool
    let ink: MonthInk

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PencilOnlyCanvas {
        let c = PencilOnlyCanvas()
        c.backgroundColor = .clear
        c.isOpaque = false
        c.drawingPolicy = .pencilOnly
        c.isScrollEnabled = false
        c.tool = PKInkingTool(.pen, color: .black, width: 2.2)
        c.delegate = context.coordinator
        return c
    }

    func updateUIView(_ c: PencilOnlyCanvas, context: Context) {
        context.coordinator.parent = self
        c.isUserInteractionEnabled = enabled
        c.overrideUserInterfaceStyle = dark ? .dark : .light
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: MonthInkCanvas?
        private var pending: DispatchWorkItem?
        private var clearing = false
        private var shifts: [String: CGFloat?] = [:]   // one placement per day while you write

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
            for (index, strokes) in byDay {
                let row = index / 7, col = index % 7
                let day = Week.day(row * 7 + col, of: p.gridStart)
                let key = Week.key(day)
                var shift: CGFloat? = shifts[key] ?? nil
                p.ink.add(strokes, cellOrigin: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH),
                          cellSize: CGSize(width: cellW, height: cellH), day: day, shift: &shift)
                shifts[key] = shift
            }
            clearing = true
            canvas.drawing = PKDrawing()
            clearing = false
        }
    }
}

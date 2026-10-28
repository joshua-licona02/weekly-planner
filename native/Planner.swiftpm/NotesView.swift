import SwiftUI
import UIKit
import PencilKit
import Combine

/// The Notes page: one long lined page (1000 wide, like the planner) that grows as you write.
/// The Pencil writes; a finger scrolls and pinches to zoom.
enum NotesPage {
    static let width: CGFloat = 1000
    static let firstLine: CGFloat = 140
    static let minHeight: CGFloat = 1400
    static let roomBelow: CGFloat = 600      // blank paper kept below your last writing

    static func height(for d: PKDrawing) -> CGFloat {
        guard !d.strokes.isEmpty else { return minHeight }
        let need = d.bounds.maxY + roomBelow
        return max(minHeight, ceil(need / Page.lineH) * Page.lineH)
    }
}

/// Draws just the part of the lined paper that's on screen (it can get very long),
/// following the canvas' scroll position and zoom.
final class NotesPaperView: UIView {
    var theme: PaperTheme = PaperTheme.all[0] { didSet { setNeedsDisplay() } }
    var zoom: CGFloat = 1 { didSet { if zoom != oldValue { setNeedsDisplay() } } }
    var offset: CGPoint = .zero { didSet { if offset != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let t = theme
        t.paper.setFill()
        ctx.fill(bounds)

        ctx.translateBy(x: -offset.x, y: -offset.y)
        ctx.scaleBy(x: zoom, y: zoom)
        let top = offset.y / zoom
        let bottom = (offset.y + bounds.height) / zoom

        if top < NotesPage.firstLine {
            let attrs: [NSAttributedString.Key: Any] = [.font: t.font(44, bold: true), .foregroundColor: t.ink]
            ("Notes" as NSString).draw(at: CGPoint(x: Page.gx, y: 22), withAttributes: attrs)
            ctx.setStrokeColor(t.border.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: Page.gx, y: 96))
            ctx.addLine(to: CGPoint(x: Page.right, y: 96))
            ctx.strokePath()
        }

        ctx.setStrokeColor(t.line.cgColor)
        ctx.setLineWidth(1.4)
        let first = max(0, floor((top - NotesPage.firstLine) / Page.lineH))
        var y = NotesPage.firstLine + first * Page.lineH
        while y <= bottom + Page.lineH {
            ctx.move(to: CGPoint(x: Page.gx, y: y))
            ctx.addLine(to: CGPoint(x: Page.right, y: y))
            y += Page.lineH
        }
        ctx.strokePath()
    }
}

final class NotesController: UIViewController, PKCanvasViewDelegate {
    private let model: PlannerModel
    private let toolPicker = PKToolPicker()
    private let paper = NotesPaperView(frame: .zero)
    private let canvas = PKCanvasView()
    private var height = NotesPage.minHeight
    private var fitScale: CGFloat = 0
    private var dirty = false
    private var saveWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init(model: PlannerModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true

        paper.frame = view.bounds
        paper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(paper)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly            // Pencil writes; fingers scroll / zoom
        canvas.drawing = NotesStore.load()            // load before the delegate is attached
        canvas.delegate = self
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.bouncesZoom = true
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        view.addSubview(canvas)
        height = NotesPage.height(for: canvas.drawing)

        toolPicker.addObserver(canvas)
        applyTheme()

        model.$themeID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &bag)
        model.$showTools
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTools() }
            .store(in: &bag)
        model.$storageGeneration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &bag)

        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: .plannerSaveAll, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        guard w > 0 else { return }
        let fit = w / NotesPage.width
        if abs(fit - fitScale) > 0.0001 {
            fitScale = fit
            canvas.minimumZoomScale = fit
            canvas.maximumZoomScale = fit * 3
            canvas.zoomScale = fit
        }
        updateContentSize()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTools()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
        toolPicker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func applyTheme() {
        paper.theme = model.theme
        // In the dark theme PencilKit flips dark ink to light automatically, like Notes in dark mode.
        canvas.overrideUserInterfaceStyle = model.theme.dark ? .dark : .light
    }

    private func updateTools() {
        guard view.window != nil else { return }
        canvas.becomeFirstResponder()
        toolPicker.setVisible(model.showTools, forFirstResponder: canvas)
    }

    private func reload() {
        saveWork?.cancel()
        canvas.drawing = NotesStore.load()
        saveWork?.cancel()
        dirty = false
        height = NotesPage.height(for: canvas.drawing)
        updateContentSize()
    }

    // MARK: scrolling + keeping the lines under the ink

    private func updateContentSize() {
        let z = canvas.zoomScale
        canvas.contentSize = CGSize(width: NotesPage.width * z, height: height * z)
        syncPaper()
    }

    private func syncPaper() {
        paper.zoom = canvas.zoomScale
        paper.offset = canvas.contentOffset
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncPaper()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
    }

    // MARK: saving (and growing the page as you write near the bottom)

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        dirty = true
        let need = NotesPage.height(for: canvasView.drawing)
        if need > height {
            height = need
            updateContentSize()
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    @objc func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard dirty else { return }
        dirty = false
        NotesStore.save(canvas.drawing)
    }
}

/// SwiftUI wrapper.
struct NotesView: UIViewControllerRepresentable {
    @EnvironmentObject var model: PlannerModel

    func makeUIViewController(context: Context) -> NotesController {
        NotesController(model: model)
    }

    func updateUIViewController(_ controller: NotesController, context: Context) {}
}

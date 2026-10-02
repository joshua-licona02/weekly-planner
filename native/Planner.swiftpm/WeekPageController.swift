import UIKit
import PencilKit

/// One planner page: the printed paper underneath, Apple's PencilKit canvas on top.
/// PencilKit does the inking, so stroke latency, prediction, pressure/tilt and palm
/// rejection are exactly what Apple Notes uses.
final class WeekPageController: UIViewController, PKCanvasViewDelegate {
    let week: Date
    private let toolPicker: PKToolPicker
    private var theme: PaperTheme
    private var showTools: Bool

    private let paper = PaperView(frame: CGRect(x: 0, y: 0, width: Page.width, height: Page.height))
    let canvas = PKCanvasView()
    private var saveWork: DispatchWorkItem?
    private var fitScale: CGFloat = 0

    /// Called with `true` while the page is zoomed in (so finger page-turns are paused).
    var onZoomChanged: ((Bool) -> Void)?

    init(week: Date, theme: PaperTheme, toolPicker: PKToolPicker, showTools: Bool) {
        self.week = week
        self.theme = theme
        self.toolPicker = toolPicker
        self.showTools = showTools
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true

        paper.week = week
        view.addSubview(paper)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly            // Pencil writes; fingers turn pages / zoom
        canvas.delegate = self
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bouncesZoom = true
        canvas.isScrollEnabled = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.drawing = InkStore.shared.load(week)
        view.addSubview(canvas)

        toolPicker.addObserver(canvas)
        applyTheme(theme)

        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds.size
        guard b.width > 0, b.height > 0 else { return }
        let fit = min(b.width / Page.width, b.height / Page.height)
        if abs(fit - fitScale) > 0.0001 {
            fitScale = fit
            canvas.minimumZoomScale = fit
            canvas.maximumZoomScale = fit * 4
            canvas.zoomScale = fit
            canvas.contentSize = CGSize(width: Page.width * fit, height: Page.height * fit)
        }
        centerContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.becomeFirstResponder()
        toolPicker.setVisible(showTools, forFirstResponder: canvas)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: theme / tools

    func applyTheme(_ t: PaperTheme) {
        theme = t
        paper.theme = t
        // In the dark theme PencilKit flips dark ink to light automatically, like Notes in dark mode.
        canvas.overrideUserInterfaceStyle = t.dark ? .dark : .light
    }

    func setToolsVisible(_ visible: Bool) {
        showTools = visible
        toolPicker.setVisible(visible, forFirstResponder: canvas)
        if visible { canvas.becomeFirstResponder() }
    }

    // MARK: zoom + keeping the paper under the ink

    private func centerContent() {
        let z = canvas.zoomScale
        let w = Page.width * z, h = Page.height * z
        let ix = max(0, (canvas.bounds.width - w) / 2)
        let iy = max(0, (canvas.bounds.height - h) / 2)
        canvas.contentInset = UIEdgeInsets(top: iy, left: ix, bottom: iy, right: ix)
        syncPaper()
    }

    private func syncPaper() {
        let z = canvas.zoomScale
        paper.transform = CGAffineTransform(scaleX: z, y: z)
        paper.center = CGPoint(x: -canvas.contentOffset.x + Page.width * z / 2,
                               y: -canvas.contentOffset.y + Page.height * z / 2)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.contentSize = CGSize(width: Page.width * canvas.zoomScale, height: Page.height * canvas.zoomScale)
        centerContent()
        let zoomed = canvas.zoomScale > canvas.minimumZoomScale * 1.02
        canvas.isScrollEnabled = zoomed
        onZoomChanged?(zoomed)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncPaper()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // re-render the printed page sharply at the new zoom level
        paper.contentScaleFactor = max(1, min(UIScreen.main.scale * scale, 4))
        paper.setNeedsDisplay()
    }

    func resetZoom() {
        canvas.setZoomScale(canvas.minimumZoomScale, animated: true)
    }

    // MARK: saving

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    @objc func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        InkStore.shared.save(canvas.drawing, week: week)
    }
}

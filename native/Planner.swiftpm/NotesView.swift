import SwiftUI
import UIKit
import PencilKit
import Combine

/// A note's page: one long lined page (1000 wide, like the planner) that grows as you write.
/// The Pencil writes; a finger scrolls and pinches to zoom.
enum NotesPage {
    static let width: CGFloat = 1000
    static let firstLine: CGFloat = 60
    static let minHeight: CGFloat = 1400
    static let roomBelow: CGFloat = 600      // blank paper kept below your last writing

    static func height(for d: PKDrawing) -> CGFloat {
        guard !d.strokes.isEmpty else { return minHeight }
        let need = d.bounds.maxY + roomBelow
        return max(minHeight, ceil(need / Page.lineH) * Page.lineH)
    }
}

// MARK: - Notes tab: list of notes + the open note

struct NotesView: View {
    @EnvironmentObject var model: PlannerModel
    @AppStorage("notesShowList") private var showList = true
    @State private var search = ""
    @State private var deleting: NoteInfo?

    var body: some View {
        let t = model.theme
        HStack(spacing: 0) {
            if showList {
                noteList
                    .frame(width: 270)
                    .transition(.move(edge: .leading))
                Rectangle().fill(Color(t.border)).frame(width: 2)
            }
            if let note = model.notes.first(where: { $0.id == model.currentNoteID }) {
                VStack(spacing: 0) {
                    titleBar(note)
                    Rectangle().fill(Color(t.border)).frame(height: 2)
                    NotesCanvas(noteID: note.id)
                }
            } else {
                emptyState
            }
        }
        .foregroundStyle(Color(t.ink))
        .background(Color(t.paper))
        .overlay(Rectangle().stroke(Color(t.border), lineWidth: 2))
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { note in
            Button("Delete “\(note.title.isEmpty ? "Untitled note" : note.title)”", role: .destructive) {
                withAnimation { model.deleteNote(note.id) }
            }
        } message: { _ in
            Text("Its handwriting is deleted too. This can't be undone (unless you have a backup).")
        }
    }

    private var filtered: [NoteInfo] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.notes : model.notes.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var noteList: some View {
        let t = model.theme
        return VStack(spacing: 0) {
            HStack {
                Text("Notes").font(.title2.bold())
                Spacer()
                Button {
                    withAnimation { model.newNote() }
                } label: {
                    Label("New note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(t.accent))
            }
            .padding(12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(t.muted))
                TextField("Search titles", text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(8)
            .background(Color(t.header), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List {
                ForEach(filtered) { note in
                    noteRow(note)
                        .listRowBackground(note.id == model.currentNoteID ? Color(t.header) : Color(t.paper))
                        .swipeActions {
                            Button(role: .destructive) { deleting = note } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) { deleting = note } label: {
                                Label("Delete note", systemImage: "trash")
                            }
                        }
                }
                if filtered.isEmpty && !model.notes.isEmpty {
                    Text("No titles match “\(search)”.")
                        .font(.callout)
                        .foregroundStyle(Color(t.muted))
                        .listRowBackground(Color(t.paper))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color(t.paper))
    }

    private func noteRow(_ note: NoteInfo) -> some View {
        Button {
            model.currentNoteID = note.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Edited \(note.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color(model.theme.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(model.theme.ink))
    }

    private func titleBar(_ note: NoteInfo) -> some View {
        let t = model.theme
        return HStack(spacing: 12) {
            Button {
                withAnimation { showList.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(.title3)
            }
            .accessibilityLabel(showList ? "Hide the list of notes" : "Show the list of notes")
            TextField("Title", text: Binding(get: { note.title }, set: { model.renameNote(note.id, to: $0) }))
                .font(.title2.bold())
                .textFieldStyle(.plain)
            Text(note.created.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(Color(t.muted))
            Button(role: .destructive) { deleting = note } label: {
                Image(systemName: "trash").font(.title3)
            }
            .accessibilityLabel("Delete this note")
        }
        .tint(Color(t.accent))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(t.header))
    }

    private var emptyState: some View {
        let t = model.theme
        return VStack(spacing: 14) {
            if !showList {
                HStack {
                    Button { withAnimation { showList = true } } label: {
                        Image(systemName: "sidebar.left").font(.title3)
                    }
                    Spacer()
                }
                .padding(14)
            }
            Spacer()
            Image(systemName: "note.text").font(.system(size: 54)).foregroundStyle(Color(t.muted))
            Text(model.notes.isEmpty ? "No notes yet" : "Pick a note from the list").font(.title3.bold())
            Button {
                withAnimation { model.newNote() }
            } label: {
                Label("New note", systemImage: "square.and.pencil").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .tint(Color(t.accent))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// SwiftUI wrapper for one note's writing page.
struct NotesCanvas: UIViewControllerRepresentable {
    @EnvironmentObject var model: PlannerModel
    let noteID: String

    func makeUIViewController(context: Context) -> NotesController {
        NotesController(model: model, noteID: noteID)
    }

    func updateUIViewController(_ controller: NotesController, context: Context) {
        controller.show(noteID)
    }
}

// MARK: - The writing page

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
    private var noteID: String
    private let toolPicker = PKToolPicker()
    private let paper = NotesPaperView(frame: .zero)
    private let canvas = PKCanvasView()
    private var height = NotesPage.minHeight
    private var fitScale: CGFloat = 0
    private var dirty = false
    private var saveWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init(model: PlannerModel, noteID: String) {
        self.model = model
        self.noteID = noteID
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
        canvas.drawing = NotesStore.load(noteID)      // load before the delegate is attached
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

    /// Switch to another note (saving this one first), starting at the top of its page.
    func show(_ id: String) {
        guard id != noteID else { return }
        saveNow()
        noteID = id
        canvas.undoManager?.removeAllActions()     // undo shouldn't reach into the previous note
        load()
        canvas.setZoomScale(canvas.minimumZoomScale, animated: false)
        canvas.contentOffset = .zero
        syncPaper()
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
        guard model.hasNote(noteID) else { return }    // the list switches us to another note
        load()
    }

    private func load() {
        saveWork?.cancel()
        canvas.drawing = NotesStore.load(noteID)
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

    /// Writing after typing a title: bring Apple's tool palette back.
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        if !canvas.isFirstResponder { updateTools() }
    }

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
        guard model.hasNote(noteID) else { return }      // deleted: don't write it back
        NotesStore.save(canvas.drawing, id: noteID)
        // (can run while SwiftUI is switching notes, so update the list just after)
        let id = noteID, m = model
        DispatchQueue.main.async { m.noteSaved(id) }
    }
}

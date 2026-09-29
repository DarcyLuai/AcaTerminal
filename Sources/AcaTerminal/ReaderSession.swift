import SwiftUI
import PDFKit
import CryptoKit
import AcaCore

/// One PDFView per open paper. SwiftUI updates never replace its document.
@MainActor final class ReaderSession: NSObject, ObservableObject {
    let paperID: UUID
    let title: String
    var fullTextSource: SourceReference?
    let pdfView = AnchorPDFView()
    @Published var loading = true
    @Published var failure: String?
    @Published var page = 0
    @Published var pageCount = 0
    @Published var progress = 0
    @Published var selection: ReaderSelection?
    @Published var outline: [ReaderOutline] = []
    @Published var focus = false
    @Published var showOutline = false
    @Published var showInspector = false
    @Published var showSearch = false
    @Published var query = ""
    @Published var matchCount = 0
    @Published var matchIndex = -1
    @Published var searching = false
    private(set) var readingScale: CGFloat = 0.92
    weak var viewport: ReaderViewport?
    private var widthPreference = "comfortable"
    private var viewportChanging = false
    var reduceMotion = false
    var documentID = ""
    var thumbnails: ReaderThumbnails?
    var onPosition: ((ReadingPosition) -> Void)?
    var onReady: (() -> Void)?
    private var matches: [PDFSelection] = []
    private var observations: [NSObjectProtocol] = []
    private var saveTask: DispatchWorkItem?
    private var searchTask: DispatchWorkItem?
    private var closed = false
    private var restoring = false
    private var markedRead = false
    private var oldPanels = (true, true)
    private var lastSaved: ReadingPosition?
    private var appliedHighlights = Set<UUID>()
    init(paper: ResearchObject) {
        paperID = paper.id; title = paper.title
        super.init()
        pdfView.displayMode = .singlePageContinuous; pdfView.displayDirection = .vertical
        pdfView.autoScales = true; pdfView.displaysPageBreaks = true
        pdfView.minScaleFactor = 0.1; pdfView.maxScaleFactor = 8
        pdfView.captureAnchor = { [weak self] in self?.capture() }
        pdfView.onMagnification = { [weak self] factor in self?.zoom(factor) }
        pdfView.onFitWidth = { [weak self] in self?.fit() }
        pdfView.restoreAnchor = { [weak self] in if let position = $0 { self?.restore(position, zoom: false) } }
        observe(.PDFViewSelectionChanged, object: pdfView) { [weak self] _ in self?.selectionChanged() }
        observe(.PDFViewPageChanged, object: pdfView) { [weak self] _ in self?.positionChanged() }
        observe(.PDFViewScaleChanged, object: pdfView) { [weak self] _ in self?.positionChanged() }
    }
    deinit { observations.forEach { NotificationCenter.default.removeObserver($0) }; saveTask?.cancel(); searchTask?.cancel() }
    func load(url: URL, position: ReadingPosition?, highlights: [ReaderHighlight]) {
        Task {
            do {
                // This document is prepared on a worker and transferred once to the UI.
                let prepared = try await Task.detached(priority: .userInitiated) { () -> (PDFDocument, String, [ReaderOutline]) in
                    guard url.isFileURL, let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw CoreError.invalid("This PDF cannot be opened. Check that the file exists and is not password protected.") }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    var hash = SHA256()
                    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
                    let identity = hash.finalize().map { String(format: "%02x", $0) }.joined()
                    var items: [ReaderOutline] = []
                    func visit(_ node: PDFOutline, depth: Int) {
                        guard items.count < 1000, depth < 12 else { return }
                        if let label = node.label, let page = node.destination?.page { items.append(.init(title: label, page: document.index(for: page), depth: depth)) }
                        for i in 0..<node.numberOfChildren { if let child = node.child(at: i) { visit(child, depth: depth + 1) } }
                    }
                    if let root = document.outlineRoot { visit(root, depth: -1) }
                    // Touch only adjacent page metadata; PDFKit owns lazy rendering.
                    _ = document.page(at: min(position?.page ?? 0, document.pageCount - 1))?.bounds(for: .cropBox)
                    return (document, identity, items)
                }.value
                guard !closed else { return }
                thumbnails = ReaderThumbnails(url: url)
                documentID = prepared.1; outline = prepared.2; pageCount = prepared.0.pageCount
                markedRead = position?.markedRead ?? false
                pdfView.document = prepared.0
                applyHighlights(highlights)
                installScrollObserver()
                observe(.PDFDocumentDidFindMatch, object: prepared.0) { [weak self] notification in
                    guard let self = self, self.searching, let match = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else { return }
                    self.matches.append(match); self.matchCount = self.matches.count
                    if self.matchIndex == -1 { self.navigateMatch(1) }
                }
                observe(.PDFDocumentDidEndFind, object: prepared.0) { [weak self] _ in self?.searching = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self, !self.closed else { return }
                    if UserDefaults.standard.object(forKey: "reader.restore") as? Bool != false, let position = position, position.documentID == self.documentID {
                        self.restore(position, zoom: true)
                    } else { self.layoutViewport(); self.go(page: 0) }
                    self.pdfView.preservesAnchor = true
                    self.loading = false
                    self.positionChanged()
                    self.onReady?(); self.onReady = nil
                }
            } catch { if !closed { loading = false; failure = error.localizedDescription } }
        }
    }
    private func observe(_ name: Notification.Name, object: AnyObject, handler: @escaping (Notification) -> Void) {
        observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { notification in handler(notification) })
    }
    private func installScrollObserver() {
        func find(_ view: NSView) -> NSScrollView? { if let scroll = view as? NSScrollView { return scroll }; return view.subviews.compactMap(find).first }
        if let clip = find(pdfView)?.contentView {
            clip.postsBoundsChangedNotifications = true
            observe(NSView.boundsDidChangeNotification, object: clip) { [weak self] _ in self?.positionChanged() }
        }
    }
    func capture() -> ReadingPosition? {
        guard let document = pdfView.document, pageCount > 0, let destination = pdfView.currentDestination, let current = destination.page else { return nil }
        let bounds = current.bounds(for: .cropBox)
        var position = ReadingPosition(paperID: paperID, documentID: documentID, page: document.index(for: current), pageCount: pageCount, normalizedScrollPosition: Double((bounds.maxY - destination.point.y) / max(1, bounds.height)), normalizedHorizontalPosition: Double((destination.point.x - bounds.minX) / max(1, bounds.width)), zoom: Double(pdfView.scaleFactor), markedRead: markedRead)
        if viewport != nil { position.readingScale = Double(readingScale) }
        return position
    }
    func restore(_ value: ReadingPosition, zoom: Bool) {
        guard !closed, let page = pdfView.document?.page(at: min(value.page, max(0, pageCount - 1))) else { return }
        restoring = true
        if zoom, viewport != nil {
            if let scale = value.readingScale { readingScale = CGFloat(scale) }
            else { readingScale = relativeScale(for: CGFloat(value.zoom), page: page) }
            layoutViewport(anchor: value)
        } else if zoom { pdfView.autoScales = false; pdfView.scaleFactor = CGFloat(value.zoom) }
        let bounds = page.bounds(for: .cropBox)
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX + bounds.width * value.normalizedHorizontalPosition, y: bounds.maxY - bounds.height * value.normalizedScrollPosition)))
        restoring = false
    }
    func positionChanged() {
        guard !closed, !loading, !restoring, !viewportChanging, let position = capture() else { return }
        if page != position.page { page = position.page; thumbnails?.request(page); if page + 1 < pageCount { thumbnails?.request(page + 1) } }
        if progress != position.progress { progress = position.progress }
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveNow() }; saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }
    func saveNow() {
        saveTask?.cancel()
        guard !closed, var position = capture() else { return }
        // Ignore timestamp-only changes; scrolling is debounced before persistence.
        if let old = lastSaved { position.lastOpenedAt = old.lastOpenedAt; if old == position { return } }
        position.lastOpenedAt = Date(); lastSaved = position; onPosition?(position)
    }
    func setRead() { markedRead = true; progress = 100; saveNow() }
    func close() { saveNow(); closed = true; pdfView.document?.cancelFindString(); searchTask?.cancel(); saveTask?.cancel() }
    func toggleFocus() {
        if !focus { oldPanels = (showOutline, showInspector); showOutline = false; showInspector = false }
        else { showOutline = oldPanels.0; showInspector = oldPanels.1 }
        focus.toggle()
    }
    var canNavigate: Bool { !loading && failure == nil && pdfView.document != nil }
    func setWidthPreference(_ preference: String) {
        guard widthPreference != preference else { return }
        widthPreference = preference; readingScale = preference == "wide" ? 1 : 0.92
        layoutViewport()
    }
    private func pageWidth(_ page: PDFPage) -> CGFloat {
        let bounds = page.bounds(for: pdfView.displayBox)
        return abs(page.rotation % 180) == 90 ? bounds.height : bounds.width
    }
    private var pagePadding: CGFloat { pdfView.pageBreakMargins.left + pdfView.pageBreakMargins.right + 4 }
    private func relativeScale(for physical: CGFloat, page: PDFPage) -> CGFloat {
        let width = max(1, viewport?.bounds.width ?? pdfView.bounds.width)
        let fullFit = max(0.01, (width - pagePadding) / max(1, pageWidth(page)))
        return physical > fullFit ? physical / fullFit : (physical * pageWidth(page) + pagePadding) / width
    }
    /// One reversible scale: below 1 expands the real PDF viewport; above 1 zooms
    /// content in the full available viewport with PDFKit's native scrollbars.
    func zoom(_ factor: CGFloat) {
        guard factor.isFinite, factor > 0, canNavigate else { return }
        if let viewport = viewport, let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) {
            let fullFit = max(0.01, (viewport.bounds.width - pagePadding) / max(1, pageWidth(page)))
            readingScale = min(max(1, pdfView.maxScaleFactor / fullFit), max(0.25, readingScale * factor))
            layoutViewport()
        } else {
            let position = capture(); pdfView.autoScales = false
            pdfView.scaleFactor = min(pdfView.maxScaleFactor, max(pdfView.minScaleFactor, pdfView.scaleFactor * factor))
            if let position = position { restore(position, zoom: false) }; positionChanged()
        }
    }
    func fit() {
        if viewport != nil { readingScale = 1; layoutViewport() }
        else { let position = capture(); pdfView.autoScales = true; if let position = position { restore(position, zoom: false) }; positionChanged() }
    }
    func layoutViewport(anchor requestedAnchor: ReadingPosition? = nil) {
        guard !closed, let viewport = viewport, viewport.bounds.width > 0, viewport.bounds.height > 0, !viewportChanging else { return }
        let anchor = requestedAnchor ?? capture()
        let reference = anchor.flatMap { pdfView.document?.page(at: $0.page) } ?? pdfView.currentPage ?? pdfView.document?.page(at: 0)
        let width = max(1, viewport.bounds.width * min(1, readingScale))
        let frame = NSRect(x: (viewport.bounds.width - width) / 2, y: 0, width: width, height: viewport.bounds.height)
        let desired = reference.map { page in
            let fit = max(0.01, (width - pagePadding) / max(1, pageWidth(page)))
            return min(pdfView.maxScaleFactor, max(pdfView.minScaleFactor, fit * max(1, readingScale)))
        }
        // SwiftUI also lays out after selection/progress updates. Reapplying an unchanged
        // viewport would restore PDFKit's transient destination over the explicit passage jump.
        if requestedAnchor == nil, pdfView.frame == frame,
           desired.map({ abs(pdfView.scaleFactor - $0) <= 0.0001 }) ?? true { return }
        viewportChanging = true
        pdfView.frame = frame
        if let desired {
            pdfView.autoScales = false
            if abs(pdfView.scaleFactor - desired) > 0.0001 { pdfView.scaleFactor = desired }
            pdfView.layoutSubtreeIfNeeded()
            if let anchor = anchor { restore(anchor, zoom: false) }
        }
        viewportChanging = false; positionChanged()
    }
    func go(page index: Int) { if let page = pdfView.document?.page(at: index) { navigate { self.pdfView.go(to: page) } } }
    /// Reuse persisted PDF coordinates only for the exact original document.
    @discardableResult func reveal(_ evidence: Evidence) -> Bool {
        guard evidence.paperID == paperID, let document = pdfView.document else { return false }
        pdfView.setCurrentSelection(nil, animate: false); pdfView.highlightedSelections = nil
        var selections: [PDFSelection] = []
        if evidence.documentID == documentID {
            for location in evidence.locations ?? [] {
                guard let page = document.page(at: location.page) else { continue }
                let box = page.bounds(for: .cropBox)
                let rect = CGRect(x: box.minX + box.width * location.x, y: box.minY + box.height * location.y, width: box.width * location.width, height: box.height * location.height)
                if let selection = page.selection(for: rect) { selections.append(selection) }
            }
        }
        let index = evidence.locations?.first?.page ?? (Int(evidence.page.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? 1) - 1
        if selections.isEmpty, let page = document.page(at: index), !evidence.quote.isEmpty, let text = page.string {
            let range = (text as NSString).range(of: evidence.quote, options: [.caseInsensitive])
            if range.location != NSNotFound, let selection = page.selection(for: range) { selections.append(selection) }
        }
        if let first = selections.first {
            for rest in selections.dropFirst() { first.add(rest) }
            pdfView.setCurrentSelection(first, animate: false); navigate { self.pdfView.go(to: first) }; return true
        }
        go(page: max(0, min(index, pageCount - 1))); return false
    }
    func startSearch() {
        searchTask?.cancel(); pdfView.document?.cancelFindString(); searching = false
        matches = []; matchCount = 0; matchIndex = -1
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { pdfView.highlightedSelections = nil; return }
        let work = DispatchWorkItem { [weak self] in guard let self = self, !self.closed else { return }; self.searching = true; self.pdfView.document?.beginFindString(term, withOptions: .caseInsensitive) }
        searchTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    func navigateMatch(_ direction: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + direction + matches.count) % matches.count
        let selected = matches[matchIndex]; selected.color = NSColor.systemYellow.withAlphaComponent(0.35)
        pdfView.highlightedSelections = [selected]
        navigate { self.pdfView.go(to: selected) }
    }
    private func navigate(_ action: () -> Void) {
        // Short native crossfade avoids a long animated journey through hundreds of pages.
        let smooth = UserDefaults.standard.object(forKey: "reader.smooth") as? Bool != false
        if smooth, !reduceMotion { pdfView.wantsLayer = true; let fade = CATransition(); fade.type = .fade; fade.duration = AcaMotion.fast; pdfView.layer?.add(fade, forKey: "navigation") }
        action(); positionChanged()
    }
    func selectionChanged() {
        guard let selected = pdfView.currentSelection, let text = selected.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, let document = pdfView.document else { selection = nil; return }
        var locations: [PDFTextLocation] = []
        for line in selected.selectionsByLine() {
            for page in line.pages {
                let rect = line.bounds(for: page); let bounds = page.bounds(for: .cropBox)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                locations.append(.init(page: document.index(for: page), x: (rect.minX - bounds.minX) / bounds.width, y: (rect.minY - bounds.minY) / bounds.height, width: rect.width / bounds.width, height: rect.height / bounds.height))
            }
        }
        let pages = selected.pages.map { document.index(for: $0) + 1 }.sorted()
        let label = pages.first.map { first in pages.last == first ? String(first) : "\(first)–\(pages.last!)" } ?? ""
        selection = ReaderSelection(quote: text, page: label, locations: locations)
    }
    func applyHighlights(_ highlights: [ReaderHighlight]) {
        guard let document = pdfView.document else { return }
        for highlight in highlights where highlight.paperID == paperID && highlight.documentID == documentID && !appliedHighlights.contains(highlight.id) {
            for location in highlight.locations {
                guard let page = document.page(at: location.page) else { continue }
                let box = page.bounds(for: .cropBox)
                let annotation = PDFAnnotation(bounds: CGRect(x: box.minX + box.width * location.x, y: box.minY + box.height * location.y, width: box.width * location.width, height: box.height * location.height), forType: .highlight, withProperties: nil)
                annotation.color = NSColor(calibratedRed: 0.75, green: 0.70, blue: 0.40, alpha: 0.35)
                annotation.contents = highlight.quote; page.addAnnotation(annotation)
            }
            appliedHighlights.insert(highlight.id)
        }
    }
}
struct ReaderSelection: Identifiable { let id = UUID(); var quote: String; var page: String; var locations: [PDFTextLocation] }
struct ReaderOutline: Identifiable { let id = UUID(); var title: String; var page: Int; var depth: Int }
final class AnchorPDFView: PDFView {
    var selectionMenu: (() -> NSMenu?)?
    var viewportManaged = false
    var onMagnification: ((CGFloat) -> Void)?
    var onFitWidth: (() -> Void)?
    override func magnify(with event: NSEvent) {
        if let action = onMagnification { action(max(0.01, 1 + event.magnification)) } else { super.magnify(with: event) }
    }
    override func smartMagnify(with event: NSEvent) { if let action = onFitWidth { action() } else { super.smartMagnify(with: event) } }
    override func zoomIn(_ sender: Any?) { if let action = onMagnification { action(1.15) } else { super.zoomIn(sender) } }
    override func zoomOut(_ sender: Any?) { if let action = onMagnification { action(1 / 1.15) } else { super.zoomOut(sender) } }
    override func menu(for event: NSEvent) -> NSMenu? { selectionMenu?() ?? super.menu(for: event) }
    var captureAnchor: (() -> ReadingPosition?)?
    var restoreAnchor: ((ReadingPosition?) -> Void)?
    var preservesAnchor = false
    private var resizeTask: DispatchWorkItem?
    private var resizing = false
    private var savedAnchor: ReadingPosition?
    override func setFrameSize(_ newSize: NSSize) {
        if viewportManaged { super.setFrameSize(newSize); return }
        let changed = abs(newSize.width - frame.width) > 1 || abs(newSize.height - frame.height) > 1
        if changed, preservesAnchor, !resizing { savedAnchor = captureAnchor?(); resizing = true }
        super.setFrameSize(newSize)
        if changed {
            resizeTask?.cancel()
            let task = DispatchWorkItem { [weak self] in guard let self = self else { return }; self.resizing = false; self.restoreAnchor?(self.savedAnchor); self.savedAnchor = nil }
            resizeTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
        }
    }
}
/// Full-size host receives only the space left by visible sibling panels.
/// Resizing this host never resizes or hides those panels.
final class ReaderViewport: NSView {
    weak var session: ReaderSession?
    init(session: ReaderSession) {
        self.session = session; super.init(frame: .zero)
        session.viewport = self; session.pdfView.viewportManaged = true
        addSubview(session.pdfView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); session?.layoutViewport() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); session?.layoutViewport() }
}
enum AcaMotion {
    static let micro = 0.12, fast = 0.16, standard = 0.22, panel = 0.24
    static func feedback(reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: micro) }
    static func transition(reduced: Bool) -> Animation { .easeInOut(duration: reduced ? 0.10 : standard) }
    static func panels(reduced: Bool) -> Animation? { reduced ? nil : .easeInOut(duration: panel) }
}

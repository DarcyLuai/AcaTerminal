import AppKit
import PDFKit
import CoreText
import CryptoKit
import AcaCore
import AcaStorage

struct Failure: Error { var message: String }
func check(_ condition: @autoclosure () throws -> Bool, _ text: String) throws { if try !condition() { throw Failure(message: text) }; print("PASS " + text) }
@main struct ReaderChecks {
    @MainActor static func wait(_ condition: () -> Bool, seconds: Double = 15) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() { if Date() > end { throw Failure(message: "Timed out waiting for PDFKit") }; try await Task.sleep(nanoseconds: 30_000_000) }
    }
    static func fixture(_ url: URL, pages: Int, scanned: Bool = false) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Failure(message: "PDF fixture creation") }
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            let title = "Research Reading Environment — Page \(index + 1)"
            let body = "Democratic states rarely fight one another.\nEvidence connects observations to a research question.\nDeterrence depends on credible signals.\n\nThis is an independently generated test document.\nSelection must retain the paper, page and source statement.\nThe researcher writes a separate claim in their own words."
            let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Times-Roman" as CFString, 15, nil), .foregroundColor: CGColor(gray: 0.12, alpha: 1)]
            let string = NSAttributedString(string: title + "\n\n" + body, attributes: attributes)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(string), CFRange(), CGPath(rect: CGRect(x: 55, y: 200, width: 500, height: 520), transform: nil), nil)
            CTFrameDraw(frame, context)
            if scanned {
                let pixelWidth = 1200, pixelHeight = 1600
                var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
                // Deterministic textured raster; substantial compressed data, no OCR.
                var state = UInt64(index + 1)
                for i in stride(from: 0, to: pixels.count, by: 4) { state = state &* 6364136223846793005 &+ 1; let shade = UInt8(200 + (state >> 40) % 55); pixels[i] = shade; pixels[i+1] = shade; pixels[i+2] = shade; pixels[i+3] = 255 }
                let provider = CGDataProvider(data: Data(pixels) as CFData)!
                let image = CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                context.draw(image, in: CGRect(x: 50, y: 35, width: 510, height: 160))
            }
            context.endPDFPage()
        }
        context.closePDF()
        if !scanned, let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
            let root = PDFOutline(); let chapter = PDFOutline(); chapter.label = "Research foundations"; chapter.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792)); root.insertChild(chapter, at: 0); doc.outlineRoot = root
            for index in 0..<300 { let mark = PDFAnnotation(bounds: CGRect(x: 50 + index % 10 * 45, y: 35 + index / 10 * 3, width: 35, height: 2), forType: .highlight, withProperties: nil); mark.color = .yellow; page.addAnnotation(mark) }
            guard doc.write(to: url) else { throw Failure(message: "Annotated fixture write") }
        }
    }
    @MainActor static func main() async {
        do {
            _ = NSApplication.shared
            let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ACA_READER_FIXTURE_DIR"] ?? NSTemporaryDirectory() + "AcaTerminal-ReaderChecks").appendingPathComponent("run-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Research-320-pages.pdf")
            try fixture(url, pages: 320)
            let hundred = directory.appendingPathComponent("Research-120-pages.pdf"); try fixture(hundred, pages: 120)
            let scanned = directory.appendingPathComponent("Scanned-24-pages.pdf"); try fixture(scanned, pages: 24, scanned: true)
            let original = try Data(contentsOf: url); let originalHash = SHA256.hash(data: original)
            let paper = ResearchObject(title: "Research-320-pages")
            let reader = ReaderSession(paper: paper)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = reader.pdfView
            let started = Date(); reader.load(url: url, position: nil, highlights: [])
            try await wait { !reader.loading }; try check(reader.failure == nil && reader.pageCount == 320, "320-page PDF opens")
            print("METRIC 320-page preparation: \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            try check((reader.capture()?.normalizedScrollPosition ?? 1) < 0.02, "First open starts at top of first page")
            let document = reader.pdfView.document!
            reader.go(page: 140); try await Task.sleep(nanoseconds: 200_000_000)
            let position = reader.capture()!
            try check(position.page == 140, "Physical page anchor captured")
            reader.zoom(1.2); try await Task.sleep(nanoseconds: 200_000_000)
            try check(reader.capture()?.page == 140, "Zoom preserves page anchor")
            reader.pdfView.setFrameSize(NSSize(width: 630, height: 620)); try await Task.sleep(nanoseconds: 300_000_000)
            try check(reader.capture()?.page == 140, "Resize preserves page anchor")
            reader.showOutline = true; reader.showInspector = true; reader.toggleFocus(); reader.toggleFocus(); try check(reader.showOutline && reader.showInspector && reader.pdfView.document === document, "Focus restores panels without reloading document")
            reader.query = "deterrence"; reader.startSearch()
            try await wait({ reader.matchCount == 320 && !reader.searching }, seconds: 30)
            try check(reader.matchCount == 320, "Async search finds matches throughout 320 pages")
            reader.navigateMatch(1); try check(reader.matchIndex == 1, "Search next navigation")
            reader.reduceMotion = true; try check(AcaMotion.panels(reduced: true) == nil, "Reduced Motion removes panel movement")
            reader.go(page: 13)
            if let selection = document.page(at: 13)?.selection(for: NSRange(location: 0, length: 80)) {
                reader.pdfView.setCurrentSelection(selection, animate: false); reader.selectionChanged()
            }
            guard let selected = reader.selection else { throw Failure(message: "Selection unavailable") }
            try check(selected.page == "14" && !selected.locations.isEmpty, "Selection carries quote, physical page and rectangles")
            let highlight = ReaderHighlight(paperID: paper.id, documentID: reader.documentID, quote: selected.quote, locations: selected.locations)
            let annotations = document.page(at: 13)!.annotations.count
            reader.applyHighlights([highlight]); reader.applyHighlights([highlight])
            try check(document.page(at: 13)!.annotations.count == annotations + selected.locations.count, "Highlights applied once")
            try check(SHA256.hash(data: try Data(contentsOf: url)) == originalHash, "Original PDF remains byte-for-byte unchanged")
            var saved: ReadingPosition?
            reader.onPosition = { saved = $0 }; reader.go(page: 88); reader.saveNow(); reader.close()
            let reopened = ReaderSession(paper: paper); window.contentView = reopened.pdfView
            reopened.load(url: url, position: saved, highlights: [highlight]); try await wait { !reopened.loading }; try await Task.sleep(nanoseconds: 300_000_000)
            try check(reopened.capture()?.page == saved?.page && reopened.capture()?.zoom == saved?.zoom, "Reopening restores saved page and zoom")
            reopened.close()
            for file in [hundred, scanned] {
                let r = ReaderSession(paper: paper); window.contentView = r.pdfView
                let start = Date(); r.load(url: file, position: nil, highlights: []); try await wait { !r.loading }
                try check(r.failure == nil, "Opens \(file.lastPathComponent)")
                print("METRIC \(file.lastPathComponent): \(Int(Date().timeIntervalSince(start) * 1000)) ms; \((try Data(contentsOf: file)).count / 1024 / 1024) MB")
                for index in stride(from: 0, to: r.pageCount, by: 3) { r.go(page: index); await Task.yield() }; r.close()
            }
            // The serial worker must drain every edit and report a stale writer.
            let dbURL = directory.appendingPathComponent("queue-\(UUID()).sqlite")
            let worker = RepositoryWorker()
            let opened: Result<ResearchDatabase, Error> = await withCheckedContinuation { continuation in worker.open(url: dbURL, seed: nil) { continuation.resume(returning: $0) } }
            var db = try opened.get(); db.objects = [paper]
            var saves = 0
            for index in 0..<12 { db.objects[0].title = "Revision \(index)"; worker.save(db) { result in if case .success = result { saves += 1 } } }
            await withCheckedContinuation { continuation in worker.drain { continuation.resume() } }
            let disk = try SQLiteRepository(url: dbURL).load()
            try check(saves == 12 && disk.objects[0].title == "Revision 11", "Background save queue drains in order")
            let rival = try SQLiteRepository(url: dbURL); var rivalData = try rival.load(); rivalData.objects[0].title = "External writer"; try rival.save(rivalData)
            let failed: Result<Void, Error> = await withCheckedContinuation { continuation in worker.save(db) { continuation.resume(returning: $0) } }
            if case .success = failed { throw Failure(message: "Stale writer was accepted") }
            let blocked: Result<Void, Error> = await withCheckedContinuation { continuation in worker.save(db) { continuation.resume(returning: $0) } }
            if case .success = blocked { throw Failure(message: "Failed queue allowed a later write") }
            try check(try SQLiteRepository(url: dbURL).load().objects[0].title == "External writer", "Failed queue never overwrites another process")
            print("Reader integration checks passed. Fixtures: \(directory.path)")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}

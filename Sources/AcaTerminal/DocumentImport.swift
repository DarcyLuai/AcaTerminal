import AppKit
import CoreText
import PDFKit
import AcaCore

/// Originals are copied locally. Word text is a derived, selectable reading edition.
enum DocumentImport {
    static let extensions = ["pdf", "docx", "doc", "rtf", "txt"]
    static func prepare(_ original: URL, directory: URL, id: UUID) throws -> ResearchObject {
        let ext = original.pathExtension.lowercased()
        guard original.isFileURL, extensions.contains(ext) else { throw CoreError.invalid("Choose a PDF, Word, RTF or text file.") }
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let copy = folder.appendingPathComponent(original.lastPathComponent)
            try FileManager.default.copyItem(at: original, to: copy)
            let reading: URL
            if ext == "pdf" {
                guard let document = PDFDocument(url: copy), !document.isLocked, document.pageCount > 0 else { throw CoreError.invalid("This PDF cannot be opened. Check that the file exists and is not password protected.") }
                reading = copy
            } else {
                reading = folder.appendingPathComponent("reading.pdf")
                try makeReadingEdition(copy, output: reading)
            }
            var object = ResearchObject(title: original.deletingPathExtension().lastPathComponent)
            object.id = id
            object.sources = [.init(provider: "local-pdf", externalID: id.uuidString, url: reading, metadata: ["originalPath": original.standardizedFileURL.path, "readingEdition": ext == "pdf" ? "original" : "text"])]
            if ext != "pdf" { object.sources.append(.init(provider: "local-document", externalID: id.uuidString, url: copy, metadata: ["format": ext])) }
            return object
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    static func makeReadingEdition(_ url: URL, output: URL) throws {
        let ext = url.pathExtension.lowercased()
        let type: NSAttributedString.DocumentType = ext == "docx" ? .officeOpenXML : ext == "doc" ? .docFormat : ext == "rtf" ? .rtf : .plain
        let original = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        let text = original.string.replacingOccurrences(of: "\u{fffc}", with: "[Figure — open original document]")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoreError.invalid("No readable text was found in this document. Export it as PDF to preserve its pages.") }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 9
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw CoreError.invalid("Could not prepare the document for reading.") }
        var offset = 0
        while offset < attributed.length {
            let path = CGPath(rect: page.insetBy(dx: 54, dy: 54), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            let range = CTFrameGetVisibleStringRange(frame)
            guard range.length > 0 else { throw CoreError.invalid("Could not prepare the document for reading.") }
            context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(page)
            CTFrameDraw(frame, context); context.endPDFPage(); offset += range.length
        }
        context.closePDF()
    }
}

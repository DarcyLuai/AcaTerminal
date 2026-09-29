import AppKit
import PDFKit
import AcaCore

func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
    guard try condition() else { throw NSError(domain: label, code: 1) }
    print("PASS " + label)
}
@main struct DocumentChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let documents = root.appendingPathComponent("managed")
        let docx = root.appendingPathComponent("Study.docx")
        let before = try Data(contentsOf: docx)
        let id = UUID()
        let object = try DocumentImport.prepare(docx, directory: documents, id: id)
        try check(object.title == "Study" && object.authors.isEmpty && object.doi == nil && object.year == nil, "Word imports without bibliographic fields")
        let original = object.sources.first { $0.provider == "local-document" }!.url!
        let reading = object.sources.first { $0.provider == "local-pdf" }!.url!
        try check(try Data(contentsOf: original) == before && Data(contentsOf: docx) == before, "Original Word bytes preserved")
        let pdf = PDFDocument(url: reading)!
        try check(pdf.pageCount > 1 && pdf.string?.contains("Evidence supports our hypothesis") == true, "Word reading edition paginates and has selectable text")
        let selected = pdf.findString("Evidence supports our hypothesis", withOptions: []).first
        try check(selected?.string == "Evidence supports our hypothesis" && selected?.pages.isEmpty == false, "Word excerpt retains readable quote and a page")
        let importedPDF = try DocumentImport.prepare(reading, directory: documents, id: UUID())
        let managedPDF = importedPDF.sources[0].url!
        try check(try Data(contentsOf: reading) == Data(contentsOf: managedPDF), "PDF copy is byte-identical")
        try FileManager.default.removeItem(at: docx)
        try check(FileManager.default.fileExists(atPath: original.path) && PDFDocument(url: managedPDF) != nil, "Managed documents remain readable after source is moved")
        let empty = root.appendingPathComponent("Empty.txt"); try "".write(to: empty, atomically: true, encoding: .utf8)
        let failedID = UUID(); var rejected = false
        do { _ = try DocumentImport.prepare(empty, directory: documents, id: failedID) } catch { rejected = true }
        try check(rejected && !FileManager.default.fileExists(atPath: documents.appendingPathComponent(failedID.uuidString).path), "Failed empty import leaves no managed document")
        _ = NSApplication.shared
        var invoked = ""
        let menu = ReaderContextMenu.make([("Highlight", { invoked = "highlight" }), ("Note", { invoked = "note" })])
        menu.performActionForItem(at: 1)
        try check(invoked == "note", "Native context menu invokes chosen annotation action")
        let text = root.appendingPathComponent("Notes.txt"); try "Simple text selection and notes.".write(to: text, atomically: true, encoding: .utf8)
        let textObject = try DocumentImport.prepare(text, directory: documents, id: UUID())
        try check(PDFDocument(url: textObject.sources[0].url!)?.string?.contains("Simple text selection") == true, "Plain text supports the same selectable reading surface")
        print("Document checks passed")
    }
}

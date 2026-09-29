import AppKit
import PDFKit
import CoreText
import CryptoKit
import AcaCore
import AcaStorage
import AcaConnectors
struct FlowError: Error { var message: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws { if try !condition() { throw FlowError(message: message) }; print("PASS " + message) }
@main struct ResearchMarkFlowChecks {
    @MainActor static func wait(_ test: () -> Bool) async throws {
        let end = Date().addingTimeInterval(15)
        while !test() { if Date() > end { throw FlowError(message: "PDF preparation timeout") }; try await Task.sleep(nanoseconds: 30_000_000) }
    }
    @MainActor static func main() async {
        do {
            _ = NSApplication.shared
            let dir = URL(fileURLWithPath: CommandLine.arguments[1]); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "prepare"
            let native = dir.appendingPathComponent("project.texflow"), pdf = dir.appendingPathComponent("source.pdf"), databaseURL = dir.appendingPathComponent("research.sqlite")
            if mode == "migrate" {
                let old = try SQLiteRepository(url: databaseURL); let db = try old.load(); try check(db.formatVersion == 5, "Actual build 8 database opens in format 5"); try old.save(db)
                try check(try SQLiteRepository(url: databaseURL).load() == db, "Actual build 8 migrated database survives reopen"); return
            }
            if mode == "prepare" {
                var box = CGRect(x:0,y:0,width:612,height:792); let context = CGContext(pdf as CFURL, mediaBox:&box,nil)!
                for _ in 0..<20 { context.beginPDFPage(nil); let line = CTLineCreateWithAttributedString(NSAttributedString(string:"Persistence increases exposure when residual risk carries over.",attributes:[.font:CTFontCreateWithName("Times-Roman" as CFString,15,nil)])); context.textPosition=CGPoint(x:45,y:700); CTLineDraw(line,context);context.endPDFPage() };context.closePDF()
                let projectJSON: [String:Any] = ["version":13,"documentSchemaVersion":13,"documentId":"e2e-document","metadata":["title":"Research Marks E2E"],"references":[],"bibliography":"","content":["type":"doc","attrs":["documentId":"e2e-document","documentSchemaVersion":13,"researchObjects":[["id":"CLAIM-003","type":"claim","anchorNodeId":"p-claim","createdAt":"2026-09-29T00:00:00Z"]]],"content":[["type":"paragraph","attrs":["nodeId":"p-claim"],"content":[["type":"text","text":"Persistence clusters risky actions temporally."]]]]]]
                try JSONSerialization.data(withJSONObject:projectJSON,options:.prettyPrinted).write(to:native)
                var db = ResearchDatabase(); let project = ResearchProject(title:"Research Marks E2E"); db.projects=[project]
                let connection=AcaTexConnection(projectID:project.id,documentID:"e2e-document",fileURL:native);db.acaTexConnections=[connection]
                try db.ingestMarks(AcaTexProjectReader().readProject(at:native),connectionID:connection.id)
                var paper=ResearchObject(title:"Persistence — fixture source");paper.sources=[.init(provider:"local-pdf",externalID:pdf.path,url:pdf)];db.objects=[paper]
                let session=ReaderSession(paper:paper);let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false);window.contentView=session.pdfView
                session.load(url:pdf,position:nil,highlights:[]);try await wait{!session.loading}
                try check(session.failure == nil,"Real PDFKit loads end-to-end source")
                session.go(page:16);let page=session.pdfView.document!.page(at:16)!;session.pdfView.setCurrentSelection(page.selection(for:NSRange(location:0,length:page.numberOfCharacters)),animate:false);session.selectionChanged()
                guard let selected=session.selection else {throw FlowError(message:"Selection missing")}
                var evidence=Evidence(paperID:paper.id,page:selected.page,quote:selected.quote,relationship:.qualifies);evidence.documentID=session.documentID;evidence.locations=selected.locations
                try db.saveEvidence(evidence,projectID:project.id,claimID:db.claims[0].id)
                let exported=try db.exportMarks(connectionID:connection.id,claimIDs:[db.claims[0].id]);try ResearchMarkCodec.encode(exported).write(to:dir.appendingPathComponent("exchange.acaresearch.json"))
                let repo=try SQLiteRepository(url:databaseURL);_=try repo.load();try repo.save(db);session.close()
                try check(selected.page == "17" && !selected.locations.isEmpty,"AcaTex Claim → PDF selection → qualified evidence → exchange")
                try Data(SHA256.hash(data:Data(contentsOf:pdf))).write(to:dir.appendingPathComponent("pdf.hash"))
                try check(try SQLiteRepository(url:databaseURL).load().binding(for:db.claims[0].id)?.externalID == "CLAIM-003","Stable external ID survives first process save")
            } else {
                let repo=try SQLiteRepository(url:databaseURL);var db=try repo.load();let id=db.claims[0].id, connection=db.acaTexConnections![0]
                try db.ingestMarks(AcaTexProjectReader().readProject(at:native),connectionID:connection.id)
                try check(db.claims.count == 1 && db.claims[0].id == id && db.claims[0].text.hasPrefix("Author revised:"),"AcaTex edited real native file → same logical Claim update")
                try check(db.relationship(evidenceID:db.evidence[0].id,claimID:id) == .qualifies,"Cross-app restart retains evidence relationship")
                try repo.save(db)
                let session=ReaderSession(paper:db.objects[0]);let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false);window.contentView=session.pdfView;session.load(url:pdf,position:nil,highlights:[]);try await wait{!session.loading}
                try check(session.reveal(db.evidence[0]),"Reopened Claim → Reader exact selection resolves")
                let selection=session.pdfView.currentSelection
                try check(selection?.string?.trimmingCharacters(in:.whitespacesAndNewlines) == db.evidence[0].quote.trimmingCharacters(in:.whitespacesAndNewlines) && selection?.pages.first.flatMap { session.pdfView.document?.index(for:$0) } == 16,"Exact source quote and physical page 17 restored in PDFKit")
                try check(try Data(SHA256.hash(data:Data(contentsOf:pdf))) == Data(contentsOf:dir.appendingPathComponent("pdf.hash")),"Original PDF unchanged across entire cross-app workflow")
                session.close()
            }
        } catch { print("FAIL \(error)");exit(1) }
    }
}

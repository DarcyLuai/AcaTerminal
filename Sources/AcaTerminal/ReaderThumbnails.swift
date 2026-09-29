import AppKit
import PDFKit

/// A separate, serially owned PDFDocument; the displayed document is never rendered
/// from a worker thread. Bounded cache, adjacent-page preparation, no full-book raster.
final class ReaderThumbnails {
    private let queue = DispatchQueue(label: "org.acaterminal.pdf-preparation", qos: .utility)
    private var document: PDFDocument?
    private let url: URL
    private let cache = NSCache<NSNumber, NSImage>()
    init(url: URL) { self.url = url; cache.countLimit = 12; cache.totalCostLimit = 4 * 1024 * 1024 }
    func request(_ page: Int, completion: @escaping (NSImage?) -> Void = { _ in }) {
        queue.async { [self] in
            if let image = cache.object(forKey: NSNumber(value: page)) { DispatchQueue.main.async { completion(image) }; return }
            if document == nil { document = PDFDocument(url: url) }
            let image = document?.page(at: page)?.thumbnail(of: NSSize(width: 116, height: 155), for: .cropBox)
            if let image = image { cache.setObject(image, forKey: NSNumber(value: page), cost: 116 * 155 * 4) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}

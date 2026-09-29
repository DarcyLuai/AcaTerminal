import Foundation
import CryptoKit
import AcaCore

public enum FullTextDownload {
    public static func safeURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host.range(of: #"^[0-9.:]+$"#, options: .regularExpression) == nil else { return false }
        return true
    }
    public static func download(_ location: FullTextLocation, directory: URL) async throws -> URL {
        guard location.accessType == .openAccess, location.isDirectPDF, safeURL(location.url) else { throw CoreError.invalid("This location must be opened in your browser.") }
        let name = SHA256.hash(data: Data(location.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".pdf"
        let file = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: PublicPDFRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(for: URLRequest(url: location.url))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CoreError.invalid("The open-access PDF could not be downloaded. Try another location or open its source page.") }
        return try await Task.detached(priority: .userInitiated) {
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 250 * 1024 * 1024 else { throw CoreError.invalid("This PDF exceeds the 250 MB download limit. Download it in your browser and import locally.") }
            let handle = try FileHandle(forReadingFrom: temporary); defer { try? handle.close() }
            guard let prefix = try handle.read(upToCount: 1024), prefix.range(of: Data("%PDF-".utf8)) != nil else { throw CoreError.invalid("The source returned a webpage instead of a PDF. Open it in your browser.") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: temporary, to: file) }
            return file
        }.value
    }
}
private final class PublicPDFRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, FullTextDownload.safeURL(url) else { completionHandler(nil); return }
        completionHandler(URLRequest(url: url)) // No cookies, credentials or provider API key.
    }
}

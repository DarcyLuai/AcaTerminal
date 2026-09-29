import Foundation
import CryptoKit
import AcaCore

/// Downloads only the official library attachment endpoint, never publisher URLs.
public enum ZoteroAttachment {
    public static func endpoint(for source: SourceReference) throws -> URL {
        let parts = source.externalID.split(separator: ":").map(String.init)
        guard source.provider == "zotero-pdf", parts.count == 3, ["local", "web"].contains(parts[0]), parts[1].range(of: #"^users/[0-9]+$"#, options: .regularExpression) != nil, parts[2].range(of: #"^[A-Z0-9]{8}$"#, options: .regularExpression) != nil, parts[0] != "local" || parts[1] == "users/0" else { throw CoreError.invalid("Invalid Zotero attachment identifier.") }
        return URL(string: (parts[0] == "local" ? "http://127.0.0.1:23119/api/" : "https://api.zotero.org/") + parts[1] + "/items/" + parts[2] + "/file")!
    }
    public static func cacheFilename(for source: SourceReference) -> String {
        let version = [source.metadata["md5"], source.metadata["version"]].compactMap { $0 }.first { !$0.isEmpty } ?? "0"
        return SHA256.hash(data: Data((source.externalID + ":" + version).utf8)).map { String(format: "%02x", $0) }.joined() + ".pdf"
    }
    public static func download(source: SourceReference, apiKey: String?, directory: URL) async throws -> URL {
        let endpoint = try endpoint(for: source)
        return try await Task.detached(priority: .userInitiated) {
            let name = cacheFilename(for: source)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) { return destination }
            var request = URLRequest(url: endpoint)
            request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
            if endpoint.scheme == "https", let key = apiKey { request.setValue(key, forHTTPHeaderField: "Zotero-API-Key") }
            let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config, delegate: AttachmentRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let temporary: URL; let response: URLResponse
            do { (temporary, response) = try await session.download(for: request) }
            catch { throw CoreError.invalid("Unable to download the Zotero PDF. Check the connection and file access permissions, or attach a local PDF.") }
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CoreError.invalid("Zotero could not provide this attachment. Enable local API access, check file permissions, or attach the PDF manually. WebDAV-only files may not be available through Zotero File Storage.") }
            let handle = try FileHandle(forReadingFrom: temporary); defer { try? handle.close() }
            guard let prefix = try handle.read(upToCount: 1024), prefix.range(of: Data("%PDF-".utf8)) != nil else { throw CoreError.invalid("The attachment response was not a PDF.") }
            try handle.seek(toOffset: 0)
            var md5 = Insecure.MD5()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); md5.update(data: data) }
            let actual = md5.finalize().map { String(format: "%02x", $0) }.joined()
            if let expected = source.metadata["md5"], !expected.isEmpty, expected.lowercased() != actual { throw CoreError.invalid("The Zotero file differs from the imported attachment version. Sync metadata again before opening it.") }
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: temporary, to: destination) }
            return destination
        }.value
    }
    /// A fresh request prevents credential propagation onto signed storage URLs.
    public static func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased(), host == "api.zotero.org" || host.hasSuffix(".zotero.org") || host.hasSuffix(".amazonaws.com") else { return nil }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    }
}
private final class AttachmentRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(ZoteroAttachment.redirectedRequest(request)) }
}

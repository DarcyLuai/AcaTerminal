import Foundation
import AcaCore
public protocol HTTPTransport { func data(for request: URLRequest) async throws -> Data }
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public actor HTTPClient: HTTPTransport {
    private let session: URLSession
    private var nextAllowed: [String: Date] = [:]
    public init() {
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> Data {
        guard let host = request.url?.host, request.url?.scheme == "https" || (request.url?.scheme == "http" && host == "127.0.0.1" && request.url?.port == 23119) else { throw CoreError.invalid("Connector URL is not allowed.") }
        if let until = nextAllowed[host], until > Date() { throw CoreError.invalid("This service asked us to wait until \(until.formatted(date: .omitted, time: .standard)). Your saved research remains available.") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { if error is CancellationError { throw error }; throw CoreError.invalid("Could not reach \(host). Check your connection; your saved research is still available.") }
        guard let http = response as? HTTPURLResponse else { throw CoreError.invalid("The service returned an invalid response.") }
        if let value = http.value(forHTTPHeaderField: "Backoff"), let seconds = Double(value) { nextAllowed[host] = Date().addingTimeInterval(max(0, seconds)) }
        if http.statusCode == 429 || http.statusCode == 503 {
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
            nextAllowed[host] = Date().addingTimeInterval(max(1, seconds))
            throw CoreError.invalid("\(host) is busy or rate limited. Retry after \(Int(seconds)) seconds.")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw CoreError.invalid("\(host) denied access. Check the API key and read permissions, or enable Zotero’s local API.") }
            if http.statusCode == 404 { throw CoreError.invalid("No matching record was found at \(host).") }
            throw CoreError.invalid("\(host) returned HTTP \(http.statusCode). Saved data has not been changed.")
        }
        return data
    }
}

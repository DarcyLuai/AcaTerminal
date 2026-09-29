import Foundation
import AcaCore

/// Personal developer-client flow. Never distribute a shared client secret in the app.
/// A production registered HTTPS callback adapter can feed the same validation/exchange.
public struct ORCIDAuthorization {
    public let clientID: String
    public let redirectURI: URL
    public let state: String
    public let createdAt: Date
    public init(clientID: String, redirectURI: URL) throws {
        guard !clientID.isEmpty, redirectURI.scheme == "https", redirectURI.host != nil, redirectURI.query == nil, redirectURI.fragment == nil, redirectURI.user == nil else { throw CoreError.invalid("Configure a client ID and exact registered HTTPS redirect URI.") }
        self.clientID = clientID; self.redirectURI = redirectURI; state = UUID().uuidString + UUID().uuidString; createdAt = Date()
    }
    public var url: URL {
        var url = URLComponents(string: "https://orcid.org/oauth/authorize")!
        url.queryItems = [.init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"), .init(name: "scope", value: "/authenticate"), .init(name: "redirect_uri", value: redirectURI.absoluteString), .init(name: "state", value: state)]
        return url.url!
    }
    public func code(from callback: URL, now: Date = Date()) throws -> String {
        guard now.timeIntervalSince(createdAt) < 600, callback.scheme == redirectURI.scheme, callback.host == redirectURI.host, callback.port == redirectURI.port, callback.path == redirectURI.path, callback.user == nil, callback.fragment == nil else { throw CoreError.invalid("This OAuth callback has expired or does not match the registered redirect.") }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state, !items.contains(where: { $0.name == "error" }), items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw CoreError.invalid("ORCID authorization was cancelled or the callback state is invalid.") }
        return code
    }
}
public struct ORCIDOAuthClient {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport = HTTPClient()) { self.transport = transport }
    public func exchange(_ authorization: ORCIDAuthorization, callback: URL, personalClientSecret: String, credentials: CredentialStore) async throws -> ResearcherIdentity {
        let code = try authorization.code(from: callback)
        let values = ["client_id": authorization.clientID, "client_secret": personalClientSecret, "grant_type": "authorization_code", "code": code, "redirect_uri": authorization.redirectURI.absoluteString]
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values.sorted { $0.key < $1.key }.map { $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "") }.joined(separator: "&")
        var request = URLRequest(url: URL(string: "https://orcid.org/oauth/token")!); request.httpMethod = "POST"; request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = try JSONDecoder().decode(Token.self, from: await transport.data(for: request))
        guard !token.access_token.isEmpty else { throw CoreError.invalid("ORCID did not return an access token.") }
        let id = try ORCIDIdentity.normalize(token.orcid)
        try credentials.write(token.access_token, for: "orcid.accessToken")
        return .init(name: token.name ?? "Researcher", orcid: id, authenticated: true)
    }
    private struct Token: Decodable { var access_token: String; var orcid: String; var name: String? }
}

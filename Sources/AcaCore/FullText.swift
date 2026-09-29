import Foundation

public enum AccessType: String, Codable { case local, library, openAccess, institutional, landingPage }
public enum PaperVersion: String, Codable {
    case published, accepted, preprint, unknown
    public var title: String { switch self { case .published: return "Published version"; case .accepted: return "Accepted manuscript"; case .preprint: return "Preprint"; case .unknown: return "Version unspecified" } }
    public init(apiValue: String?) { switch apiValue { case "publishedVersion": self = .published; case "acceptedVersion": self = .accepted; case "submittedVersion": self = .preprint; default: self = .unknown } }
}
public struct FullTextLocation: Codable, Hashable, Identifiable {
    public var id: String { provider + "|" + url.absoluteString + "|" + version.rawValue }
    public var provider: String
    public var url: URL
    public var accessType: AccessType
    public var version: PaperVersion
    public var isDirectPDF: Bool
    public var sourceID: String?
    public var hostType: String?
    public init(provider: String, url: URL, accessType: AccessType, version: PaperVersion = .unknown, isDirectPDF: Bool, sourceID: String? = nil, hostType: String? = nil) {
        self.provider = provider; self.url = url; self.accessType = accessType; self.version = version; self.isDirectPDF = isDirectPDF; self.sourceID = sourceID; self.hostType = hostType
    }
    public var priority: Int {
        if accessType == .local { return 0 }; if accessType == .library { return 1 }
        if accessType == .openAccess && isDirectPDF { return version == .published ? 2 : version == .accepted ? 3 : version == .preprint ? 4 : 5 }
        return accessType == .institutional ? 6 : 7
    }
}
public protocol FullTextProvider: Connector { func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] }
public struct FullTextResolution {
    public var locations: [FullTextLocation]
    public var failures: [String]
    public init(locations: [FullTextLocation], failures: [String] = []) { self.locations = locations; self.failures = failures }
}
public struct FullTextResolver {
    public init() {}
    public func resolve(_ object: ResearchObject, providers: [FullTextProvider]) async -> FullTextResolution {
        var locations: [FullTextLocation] = []; var failures: [String] = []
        for provider in providers {
            do { locations += try await provider.resolve(object) }
            catch { failures.append(provider.displayName + ": " + error.localizedDescription) }
        }
        var seen = Set<String>()
        return .init(locations: locations.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }.filter { seen.insert($0.id).inserted }, failures: failures)
    }
}

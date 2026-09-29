import Foundation
public enum SubmissionStatus: String, Codable, CaseIterable {
    case draft, submitted, technicalCheck, withEditor, underReview, reviewsComplete, decisionPending, revisionRequested, revisionSubmitted, accepted, rejected, withdrawn, unknown
    public var title: String {
        switch self {
        case .technicalCheck: return "Technical check"
        case .withEditor: return "With editor"
        case .underReview: return "Under review"
        case .reviewsComplete: return "Reviews complete"
        case .decisionPending: return "Decision pending"
        case .revisionRequested: return "Revision requested"
        case .revisionSubmitted: return "Revision submitted"
        default: return rawValue.capitalized
        }
    }
    public static func normalize(_ raw: String) -> Self {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: Self] = ["required reviews completed": .reviewsComplete, "reviews completed": .reviewsComplete, "awaiting decision": .decisionPending, "awaiting ae assignment": .withEditor, "major revision": .revisionRequested, "minor revision": .revisionRequested]
        return aliases[value] ?? allCases.first { $0.title.lowercased() == value || $0.rawValue.lowercased() == value } ?? .unknown
    }
    public var isActive: Bool { ![.accepted, .rejected, .withdrawn, .draft].contains(self) }
}
public struct SubmissionEvent: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var status: SubmissionStatus
    public var statusRaw: String
    public var source: String
    public init(date: Date, status: SubmissionStatus, statusRaw: String, source: String) { self.date = date; self.status = status; self.statusRaw = statusRaw; self.source = source }
}
public struct Submission: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var manuscriptID: UUID?
    public var externalManuscriptID: String
    public var title: String
    public var journal: String
    public var submittedAt: Date
    /// True when submittedAt is the local recording date, not a known submission date.
    public var submissionDateUnknown: Bool?
    public var updatedAt: Date
    public var status: SubmissionStatus
    public var statusRaw: String
    public var source: String
    public var portalURL: URL?
    public var history: [SubmissionEvent]
    public init(title: String, journal: String, externalManuscriptID: String = "", submittedAt: Date = Date(), status: SubmissionStatus = .submitted, statusRaw: String = "", portalURL: URL? = nil, source: String = "manual") {
        self.title = title; self.journal = journal; self.externalManuscriptID = externalManuscriptID; self.submittedAt = submittedAt; self.updatedAt = submittedAt
        self.status = status; self.statusRaw = statusRaw; self.portalURL = portalURL; self.source = source
        history = [.init(date: submittedAt, status: status, statusRaw: statusRaw, source: source)]
    }
    @discardableResult public mutating func record(status: SubmissionStatus, raw: String, at date: Date = Date()) throws -> Bool {
        guard date >= submittedAt, date >= (history.last?.date ?? submittedAt), date <= Date().addingTimeInterval(60) else { throw CoreError.invalid("A status update must follow the last event and cannot be in the future.") }
        guard status != self.status || raw != statusRaw else { return false }
        self.status = status; statusRaw = raw; updatedAt = date
        history.append(.init(date: date, status: status, statusRaw: raw, source: source)); return true
    }
}

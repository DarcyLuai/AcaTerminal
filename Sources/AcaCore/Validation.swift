import Foundation
public extension ResearchDatabase {
    func validate() throws {
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        guard unique(objects.map(\.id)), unique(projects.map(\.id)), unique(claims.map(\.id)), unique(evidence.map(\.id)), unique(notes.map(\.id)), unique(submissions.map(\.id)), unique(collections.map(\.id)) else { throw CoreError.invalid("Duplicate internal identifiers found. No changes were saved.") }
        let objectIDs = Set(objects.map(\.id)), projectIDs = Set(projects.map(\.id)), evidenceIDs = Set(evidence.map(\.id))
        guard objects.allSatisfy({ Set($0.projects).isSubset(of: projectIDs) }),
              claims.allSatisfy({ projectIDs.contains($0.projectID) && Set($0.sources).isSubset(of: objectIDs) && Set($0.evidence).isSubset(of: evidenceIDs) }),
              evidence.allSatisfy({ objectIDs.contains($0.paperID) }), notes.allSatisfy({ objectIDs.contains($0.paperID) }),
              submissions.allSatisfy({ $0.manuscriptID.map { objectIDs.contains($0) } ?? true }),
              citationSnapshots.allSatisfy({ objectIDs.contains($0.objectID) }) else { throw CoreError.invalid("A research link points to a missing object. No changes were saved.") }
        guard (readingStates ?? []).allSatisfy({ objectIDs.contains($0.paperID) && $0.page >= 0 && $0.page < $0.pageCount && $0.zoom.isFinite && $0.zoom > 0 && (0...1).contains($0.normalizedScrollPosition) && (0...1).contains($0.normalizedHorizontalPosition) }),
              (highlights ?? []).allSatisfy({ objectIDs.contains($0.paperID) }),
              evidence.allSatisfy({ $0.projectID.map { projectIDs.contains($0) } ?? true }) else { throw CoreError.invalid("A reading record has an invalid research link or position.") }
        guard (readingStates ?? []).allSatisfy({ $0.readingScale.map { $0.isFinite && $0 > 0 && $0 <= 100 } ?? true }) else { throw CoreError.invalid("Invalid reader magnification.") }
        guard unique((readingStates ?? []).map(\.paperID)), unique((highlights ?? []).map(\.id)) else { throw CoreError.invalid("Duplicate reading records.") }
        func validLocation(_ location: PDFTextLocation) -> Bool {
            location.page >= 0 && [location.x, location.y, location.width, location.height].allSatisfy { $0.isFinite } && location.width > 0 && location.height > 0
        }
        guard (highlights ?? []).allSatisfy({ !$0.documentID.isEmpty && $0.locations.allSatisfy(validLocation) }), evidence.allSatisfy({ ($0.locations ?? []).allSatisfy(validLocation) }) else { throw CoreError.invalid("Invalid PDF text location.") }
        let events = citationEvents ?? [], states = citationStates ?? []
        guard unique(events.map(\.id)), unique(states.map(\.id)), events.allSatisfy({ objectIDs.contains($0.citedWorkID) && !$0.citingWorkID.isEmpty }), states.allSatisfy({ objectIDs.contains($0.citedWorkID) && unique($0.knownCitingWorks) }), citationSnapshots.allSatisfy({ $0.metrics.citationCount >= 0 }) else { throw CoreError.invalid("Invalid citation history or duplicate citation event.") }
        try validateAdvanced()
        try validateResearchMarks()
        for submission in submissions {
            guard let latest = submission.history.last, latest.status == submission.status, latest.statusRaw == submission.statusRaw,
                  submission.history.allSatisfy({ $0.date >= submission.submittedAt }),
                  zip(submission.history, submission.history.dropFirst()).allSatisfy({ $0.date <= $1.date }) else { throw CoreError.invalid("Submission history is inconsistent. No changes were saved.") }
        }
    }
}

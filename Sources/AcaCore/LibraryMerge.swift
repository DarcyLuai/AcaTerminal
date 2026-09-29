import Foundation
public enum ImportDecision: Equatable { case merge(UUID), separate }
public extension ResearchDatabase {
    /// Stage in a value copy; publish only after all ambiguous identities have been resolved.
    mutating func apply(_ batch: LibraryImport, decisions: [UUID: ImportDecision] = [:]) throws {
        var next = self; var remap: [UUID: UUID] = [:]; let resolver = ResearchObjectResolver()
        for item in batch.objects {
            let resolution = resolver.resolve(item, in: next.objects)
            let destination: UUID?
            if let decision = decisions[item.id] {
                switch decision { case .merge(let id): destination = id; case .separate: destination = nil }
            } else {
                switch resolution {
                case .match(let id): destination = id
                case .new: destination = nil
                case .possible: throw CoreError.invalid("Review the possible duplicate: \(item.title). No records have been imported yet.")
                }
            }
            if let id = destination {
                guard let index = next.objects.firstIndex(where: { $0.id == id }) else { throw CoreError.invalid("The merge target no longer exists.") }
                next.objects[index] = resolver.merge(item, into: next.objects[index]); remap[item.id] = id
            } else { next.objects.append(item); remap[item.id] = item.id }
        }
        for var note in batch.notes {
            guard let id = remap[note.paperID] else { throw CoreError.invalid("An imported note is missing its paper.") }; note.paperID = id
            if let source = note.sourceID, let index = next.notes.firstIndex(where: { $0.sourceID == source }) { note.id = next.notes[index].id; next.notes[index] = note }
            else { next.notes.append(note) }
        }
        for collection in batch.collections {
            if let i = next.collections.firstIndex(where: { $0.id == collection.id }) { next.collections[i] = collection } else { next.collections.append(collection) }
        }
        self = next
    }
}

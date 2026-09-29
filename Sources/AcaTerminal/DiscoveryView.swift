import SwiftUI
import AcaCore

func discoveryReason(_ reason: DiscoveryReason, database: ResearchDatabase) -> String {
    switch reason.kind {
    case .sharedReferences: return trf("Shares %d references with project papers", reason.count)
    case .citesProject: return trf("Cites %d papers in this project", reason.count)
    case .relatedByProvider: return tr("Listed as related by OpenAlex")
    case .topic: return tr("Shares a tracked topic derived from project papers")
    case .author: return tr("By an author tracked from project papers")
    case .localKeywords:
        let base = trf("%d matching keywords · evaluated on this Mac", reason.count)
        if let id = reason.claimID, let claim = database.claims.first(where: { $0.id == id }) { return base + "\n" + tr(claim.researchType.title) + " · " + "“" + claim.text + "”" }
        return base
    case .recent: return tr("Published within the last 90 days")
    case .notInLibrary: return tr("Not in your Library at the last refresh")
    }
}
struct ProjectDiscoveryView: View {
    @EnvironmentObject var store: WorkspaceStore
    var project: ResearchProject
    @State private var category = DiscoveryCategory.related
    @State private var showDismissed = false
    @State private var aboutSuggestions = false
    var cache: DiscoveryCache? { store.database.discoveryCaches?.first { $0.projectID == project.id && $0.provider == "openalex" } }
    var results: [DiscoveryRecommendation] {
        let dismissed = Set((store.database.discoveryFeedback ?? []).filter { $0.projectID == project.id && $0.judgment != .relevant }.map(\.workID))
        return (cache?.recommendations ?? []).filter { $0.categories.contains(category) && (showDismissed || !dismissed.contains($0.id)) && (store.discoveryMarkID == nil || $0.markMatches?.contains(where: { $0.markID == store.discoveryMarkID }) == true) }
    }
    var body: some View {
        ProjectSurface {
            Button { store.projectTab = "Overview" } label: { Label(tr("Project papers"), systemImage: "chevron.left") }.buttonStyle(.link)
            DiscoveryRefresh(project: project)
            Picker(tr("Related research mark"), selection: $store.discoveryMarkID) { Text(tr("All project marks")).tag(nil as UUID?); ForEach(store.database.claims.filter { $0.projectID == project.id }) { claim in Text(tr(claim.researchType.title) + " · " + claim.text).tag(Optional(claim.id)) } }
            Text(tr("Private mark text is matched locally against public results. Only public paper identifiers are sent to OpenAlex.")).font(.caption).foregroundColor(.secondary)
            if let cache = cache {
                HStack { Picker(tr("For this project"), selection: $category) { ForEach(DiscoveryCategory.allCases, id: \.self) { Text(tr($0.title)).tag($0) } }.frame(maxWidth: 350); Spacer(); Toggle(tr("Include dismissed"), isOn: $showDismissed).toggleStyle(.checkbox) }
                AcaDisclosure(title: "About these suggestions", expanded: $aboutSuggestions) {
                Text(trf("Tracking %d authors and %d topics from public seed papers", cache.trackedAuthors.count, cache.trackedTopics.count)).font(.caption).foregroundColor(.secondary)
                Text(tr("Suggestions use citation links and local keyword heuristics. Potential challenges and support require your review; they are not scholarly judgments.")).font(.caption).foregroundColor(.secondary)
                }
                if results.isEmpty { Text(tr("No matches in this category yet.")).foregroundColor(.secondary) }
                LazyVStack(alignment: .leading, spacing: 26) { ForEach(results) { item in DiscoveryWorkRow(work: item.work, reasons: item.reasons, projectID: project.id, markMatches: item.markMatches ?? [], potential: item.categories.contains(.potentialChallenges) || item.potentialSupport); Divider() } }
            } else {
                Text(tr("Add published papers to this project, then discover related work.")).foregroundColor(.secondary)
            }
        }
    }
}
struct DiscoveryRefresh: View {
    @State private var details = false
    @EnvironmentObject var store: WorkspaceStore
    var project: ResearchProject
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if store.discoveryRefreshing.contains(project.id) { ProgressView().controlSize(.small); Text(tr("Discovering related works…")); Button(tr("Cancel")) { store.discoveryTasks[project.id]?.cancel() } }
                else { Button(tr("Refresh Now")) { store.refreshDiscovery(project.id) } }
                Spacer()
                if let cache = store.database.discoveryCaches?.first(where: { $0.projectID == project.id }) { Text("OpenAlex · " + cache.checkedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundColor(.secondary) }
            }
            if let error = store.discoveryErrors[project.id] { Text(tr(error)).font(.caption).foregroundColor(.secondary); Text(tr("Saved results remain available offline.")).font(.caption).foregroundColor(.secondary) }
            AcaDisclosure(title: "How discovery works", expanded: $details) {
            Text(tr("Start with published papers in this project. Discovery uses up to five public DOI / OpenAlex IDs. Your question, claims, evidence and tags are matched locally and never sent to OpenAlex.")).font(.caption).foregroundColor(.secondary)
            Text(tr("Bounded discovery: up to 200 candidates per refresh; not an exhaustive literature search. First refresh establishes a silent baseline.")).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
struct DiscoveryWorkRow: View {
    @EnvironmentObject var store: WorkspaceStore
    var work: DiscoveryWork
    var reasons: [DiscoveryReason]
    var projectID: UUID
    var markMatches: [PotentialMarkMatch] = []
    var potential = false
    @State private var why = false
    var feedback: DiscoveryJudgment? { store.database.discoveryFeedback?.first { $0.projectID == projectID && $0.workID == work.id }?.judgment }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(work.object.title).font(.system(size: 20, design: .serif)).textSelection(.enabled)
            Text(byline).font(.caption).foregroundColor(.secondary)
            Text(trf("%d citations", work.citationCount) + " · OpenAlex").font(.caption).foregroundColor(.secondary)
            if potential { Text(tr("Potential claim connection · keyword heuristic, please verify")).font(.caption).foregroundColor(.secondary) }
            AcaDisclosure(title: "Why this paper?", expanded: $why) {
                VStack(alignment: .leading, spacing: 12) { ForEach(Array(hintLabels.enumerated()), id: \.offset) { _, label in Text(label).font(.caption).foregroundColor(.secondary).lineLimit(3) }; ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in Text(discoveryReason(reason, database: store.database)).font(.caption).textSelection(.enabled) }; if !work.object.abstract.isEmpty { Text(work.object.abstract).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled) } }
            }
            actions
        }
    }
    var hintLabels: [String] { markMatches.prefix(3).map { match in
        guard let mark = store.database.claims.first(where: { $0.id == match.markID }) else { return tr(match.suggestion) + " · " + tr("Please verify") }
        return tr(match.suggestion) + " · " + tr("Please verify") + "\n“" + mark.text + "”"
    } }
    var byline: String {
        let names = work.object.authors.prefix(3).map(\.name).joined(separator: ", ")
        let year = work.object.year.map(String.init) ?? ""
        return names + " · " + year + " · " + work.object.venue
    }
    var actions: some View {
            HStack(spacing: 12) {
                Button(tr("Open Reader")) { if let paper = store.importDiscovery(work) { store.openReader(paper) } }
                Button(tr("Add to Project")) { if store.importDiscovery(work, projectID: projectID) != nil { store.feedback(work.id, projectID: projectID, judgment: .relevant) } }
                Spacer()
                Menu {
                    Button(tr("Add to Library")) { _ = store.importDiscovery(work) }
                    if let url = work.object.sources.first(where: { $0.provider == "openalex" })?.url { Link(tr("Open Source"), destination: url) }
                    Divider()
                    Button(tr("Relevant")) { store.feedback(work.id, projectID: projectID, judgment: .relevant) }
                    Button(tr("Not Relevant")) { store.feedback(work.id, projectID: projectID, judgment: .notRelevant) }
                    Button(tr("Already known")) { store.feedback(work.id, projectID: projectID, judgment: .alreadyKnown) }
                } label: { Image(systemName: "ellipsis") }.help(tr("More actions"))
                if let feedback = feedback { Text(tr(feedback.rawValue)).font(.caption).foregroundColor(.secondary) }
            }.controlSize(.small)
    }
}
struct ProjectChangesView: View {
    @EnvironmentObject var store: WorkspaceStore
    var project: ResearchProject
    @State private var showHistory = false
    @State private var aboutChanges = false
    var sets: [LiteratureChangeSet] { (store.database.literatureChanges ?? []).filter { $0.projectID == project.id && (showHistory || $0.reviewedAt == nil) }.sorted { $0.detectedAt > $1.detectedAt } }
    var body: some View {
        ProjectSurface {
            DiscoveryRefresh(project: project)
            HStack { Text(trf("%d works since your last review", store.database.unreviewedChanges(projectID: project.id).count)); Spacer(); Toggle(tr("Show reviewed"), isOn: $showHistory).toggleStyle(.checkbox); Button(tr("Mark reviewed")) { store.reviewChanges(project.id) }.disabled(store.database.unreviewedChanges(projectID: project.id).isEmpty) }
            AcaDisclosure(title: "About these changes", expanded: $aboutChanges) {
            Text(tr("New means newly detected in this bounded search, not necessarily newly published. Potential claim connections use local keyword heuristics.")).font(.caption).foregroundColor(.secondary)
            }
            if sets.isEmpty { Text(tr("No unreviewed changes.")).foregroundColor(.secondary) }
            LazyVStack(alignment: .leading, spacing: 26) { ForEach(sets) { set in
                Text(set.detectedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundColor(.secondary)
                ForEach(set.changes) { change in
                    Text(change.kinds.map { tr($0.rawValue) }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
                    DiscoveryWorkRow(work: change.work, reasons: change.reasons, projectID: project.id, potential: change.kinds.contains(.potentialClaimChallenge) || change.kinds.contains(.potentialClaimSupport)); Divider()
                }
            } }
        }
    }
}
struct ProjectTimelineView: View {
    @EnvironmentObject var store: WorkspaceStore
    var project: ResearchProject
    struct Entry: Identifiable { var id: String; var date: Date; var title: String; var detail: String }
    var entries: [Entry] {
        var values = [Entry(id: project.id.uuidString, date: project.createdAt, title: tr("Project created"), detail: project.title)]
        values += store.database.claims.filter { $0.projectID == project.id }.map { Entry(id: $0.id.uuidString, date: $0.createdAt, title: tr("Claim"), detail: $0.text) }
        values += (store.database.claimRelations ?? []).filter { $0.projectID == project.id }.map { Entry(id: $0.id.uuidString, date: $0.createdAt, title: tr("Claim relationship"), detail: tr($0.relationship.rawValue)) }
        values += (store.database.literatureSnapshots ?? []).filter { $0.projectID == project.id }.map { Entry(id: $0.id.uuidString, date: $0.checkedAt, title: tr("Literature checked"), detail: "OpenAlex · " + trf("%d known works", $0.knownWorkIDs.count)) }
        return values.sorted { $0.date > $1.date }
    }
    var body: some View { ProjectSurface { LazyVStack(alignment: .leading, spacing: 22) { ForEach(entries) { entry in HStack(alignment: .top, spacing: 24) { Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundColor(.secondary).frame(width: 130, alignment: .leading); VStack(alignment: .leading, spacing: 7) { Text(entry.title).font(.caption).foregroundColor(.secondary); Text(entry.detail) } }; Divider() } } } }
}
struct ResearchChangesToday: View {
    @EnvironmentObject var store: WorkspaceStore
    var projects: [ResearchProject] { store.database.projects.filter { store.database.unreviewedChanges(projectID: $0.id).contains(where: \.important) } }
    var body: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                SectionCaption(text: "Research changes")
                ForEach(projects.prefix(4)) { project in
                    Button { store.showResearchChanges(project.id) } label: {
                        HStack { VStack(alignment: .leading, spacing: 8) { Text(project.title).font(.system(size: 20, design: .serif)); Text(trf("%d developments since your last review", store.database.unreviewedChanges(projectID: project.id).filter(\.important).count)).font(.caption).foregroundColor(.secondary) }; Spacer(); Text(tr("Review Changes →")) }.frame(maxWidth: .infinity)
                    }.buttonStyle(AcaButtonStyle())
                }
            }
            Divider()
        }
    }
}

import SwiftUI
import Charts
import AcaCore

struct ImpactView: View {
    @AppStorage("interfaceLanguage") private var language = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.colorScheme) private var colorScheme
    private var chartInk: Color { colorScheme == .dark ? Color(red: 0.66, green: 0.73, blue: 0.68) : Palette.accent }
    @State private var orcid = ""
    @State private var mode = "annual"
    @State private var sort = "cited"
    @State private var historyPaper: UUID?
    @AppStorage("scholar.profile") private var scholarProfile = ""
    var body: some View {
        if let id = store.selectedCitationID, let event = store.database.citationEvents?.first(where: { $0.id == id }) { CitationDetailView(event: event) }
        else {
            Page(title: tr("My Research")) {
                if let identity = store.database.identity {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(identity.name).font(.system(size: 27, design: .serif))
                            Link(identity.orcid, destination: URL(string: "https://orcid.org/" + identity.orcid)!)
                            Text(tr(identity.authenticated ? "ORCID · authenticated identity" : "ORCID · public lookup, not authenticated")).font(.caption).foregroundColor(.secondary)
                            if let url = URL(string: scholarProfile), url.scheme == "https", url.host == "scholar.google.com" { Link(tr("Google Scholar · Open Profile ↗"), destination: url).font(.caption) }
                        }
                        Spacer()
                        if store.impactRefreshing { Button(tr("Cancel refresh")) { store.cancelImpactRefresh() } }
                        else { Button(tr("Refresh Now")) { store.refreshImpact() }.disabled(store.busy) }
                    }
                    if !store.impactStatus.isEmpty { HStack { if store.impactRefreshing { ProgressView().controlSize(.small) }; Text(store.impactStatus).font(.caption).foregroundColor(.secondary) } }
                    analyticsContent
                    Divider()
                    SectionCaption(text: "New citations")
                    CitationActivityList(limit: 30)
                    Divider()
                    SectionCaption(text: trf("%d works in your library", identity.works.count))
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(identity.works) { work in
                            Button { store.openReader(work) } label: { HStack { Text(work.title).font(.system(size: 16, design: .serif)); Spacer(); Text(work.year.map(String.init) ?? "—").font(.caption).foregroundColor(.secondary) } }.buttonStyle(AcaButtonStyle())
                        }
                    }
                } else {
                    Text(tr("Connect your work to your research identity.")).font(.system(size: 25, design: .serif))
                    TextField(tr("ORCID iD"), text: $orcid).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    HStack { Button(tr("Look Up in OpenAlex")) { Task { await store.lookupResearcher(orcid) } }.disabled(orcid.isEmpty || store.busy); Button(tr("ORCID connection settings")) { store.destination = .orcid } }
                }
            }
        }
    }
    @ViewBuilder var analyticsContent: some View {
        let data = store.analytics
        let providers = Array(Set(store.database.citationSnapshots.map(\.provider) + ["openalex"])).sorted()
        RuleSection(title: "Impact") { SettingsRow(title: "Citation source") { ChoiceField(selection: $store.analyticsProvider, options: providers.map { ($0, $0 == "openalex" ? "OpenAlex" : $0) }) } }
        HStack(spacing: 42) { metric(data.citationCount.map { $0.formatted() } ?? "—", "Citations"); metric(data.thisYear.map(String.init) ?? "—", "This year"); metric(data.hIndex.map(String.init) ?? "—", "h-index"); metric(data.worksCount.formatted(), "Works") }
        if let date = data.updatedAt { Text(tr("Retrieved") + " · " + date.formatted(.dateTime.locale(L10n.locale).year().month().day())).font(.caption).foregroundColor(.secondary) }
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionCaption(text: "Citation growth"); Spacer(); Picker(tr("Chart mode"), selection: $mode) { Text(tr("By year")).tag("annual"); Text(tr("Cumulative")).tag("cumulative"); Text(tr("Local snapshots")).tag("snapshots") }.labelsHidden().frame(width: 205) }
            if mode == "snapshots" {
                Picker(tr("Paper"), selection: $historyPaper) { Text(tr("Choose a work")).tag(nil as UUID?); ForEach(data.papers) { Text($0.title).tag(Optional($0.id)) } }
                let points = data.observations.filter { $0.paperID == (historyPaper ?? data.papers.first?.id) }
                if points.count >= 2 {
                    Chart(points) { point in LineMark(x: .value(tr("Date"), point.date), y: .value(tr("Citations"), point.count)).foregroundStyle(chartInk); PointMark(x: .value(tr("Date"), point.date), y: .value(tr("Citations"), point.count)).foregroundStyle(chartInk) }.frame(height: 210)
                } else { Text(tr("Refresh again later to build a local time series.")).font(.caption).foregroundColor(.secondary) }
            } else if !data.years.isEmpty {
                Chart(data.years) { year in LineMark(x: .value(tr("Year"), String(year.year)), y: .value(tr("Citations"), mode == "annual" ? year.count : year.cumulative)).foregroundStyle(chartInk); PointMark(x: .value(tr("Year"), String(year.year)), y: .value(tr("Citations"), mode == "annual" ? year.count : year.cumulative)).foregroundStyle(chartInk) }.frame(height: 210)
                if mode == "cumulative" { Text(tr("Cumulative within available years; not lifetime citations.")).font(.caption).foregroundColor(.secondary) }
            } else { Text(tr("Annual citation data is unavailable for this provider.")).font(.caption).foregroundColor(.secondary) }
        }
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionCaption(text: "Citations by paper"); Spacer(); Picker(tr("Sort papers"), selection: $sort) { Text(tr("Most cited")).tag("cited"); Text(tr("Recently cited")).tag("recent"); Text(tr("Fastest growing")).tag("growth") }.labelsHidden().frame(width: 190) }
            let papers = Array(data.sortedPapers(by: sort).prefix(12))
            if !papers.isEmpty {
                Chart(papers) { paper in BarMark(x: .value(tr("Citations"), paper.citationCount), y: .value(tr("Paper"), String((papers.firstIndex { $0.id == paper.id } ?? 0) + 1) + ". " + String(paper.title.prefix(42)))).foregroundStyle(chartInk.opacity(0.8)) }.frame(height: CGFloat(max(150, papers.count * 32)))
                Text(tr("Top 12 shown. Recent means detected here; growth uses snapshots at least one day apart.")).font(.caption).foregroundColor(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 18) {
            SectionCaption(text: "Works by year")
            Chart(data.worksByYear) { year in BarMark(x: .value(tr("Year"), String(year.year)), y: .value(tr("Works"), year.count)).foregroundStyle(chartInk.opacity(0.75)) }.frame(height: 150)
        }
    }
    func metric(_ value: String, _ title: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(value).font(.system(size: 35, weight: .light, design: .serif)).monospacedDigit(); Text(tr(title)).font(.caption).foregroundColor(.secondary) } }
}
struct CitationActivityList: View {
    @EnvironmentObject var store: WorkspaceStore
    @AppStorage("interfaceLanguage") private var language = "system"
    var limit: Int
    var events: [CitationEvent] { Array((store.database.citationEvents ?? []).sorted { $0.detectedAt > $1.detectedAt }.prefix(limit)) }
    var body: some View {
        if events.isEmpty { Text(tr("No newly detected citations yet. The first check establishes a quiet baseline.")).font(.caption).foregroundColor(.secondary) }
        ForEach(events) { event in
            VStack(alignment: .leading, spacing: 8) {
                Text(event.citingWork.authors.prefix(2).map(\.name).joined(separator: " & ") + (event.citingWork.year.map { " · \($0)" } ?? "")).font(.caption).foregroundColor(.secondary)
                Button { store.showCitation(event.id) } label: { HStack { Text(event.citingWork.title).font(.system(size: 18, design: .serif)); if !event.seen { Circle().fill(Palette.accent).frame(width: 5, height: 5) } } }.buttonStyle(AcaButtonStyle())
                Text(trf("cited %@", store.database.objects.first { $0.id == event.citedWorkID }?.title ?? "") + " · " + event.provider).font(.caption).foregroundColor(.secondary)
                HStack { Button(tr("View")) { store.showCitation(event.id) }; Button(tr("Read paper")) { if let work = store.importCitingWork(event) { store.openReader(work) } } }.font(.caption)
            }.padding(.vertical, 8)
        }
    }
}
struct CitationDetailView: View {
    @EnvironmentObject var store: WorkspaceStore
    @AppStorage("interfaceLanguage") private var language = "system"
    var event: CitationEvent
    var body: some View {
        Page(title: event.citingWork.title, subtitle: event.citingWork.authors.map(\.name).joined(separator: ", ")) {
            Button(tr("Back to My Research")) { store.selectedCitationID = nil }
            Text([event.citingWork.venue, event.citingWork.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundColor(.secondary)
            Text(trf("cited %@", store.database.objects.first { $0.id == event.citedWorkID }?.title ?? "")).font(.headline)
            Text(tr("Detected") + " · " + event.detectedAt.formatted(.dateTime.locale(L10n.locale).year().month().day()) + " · " + event.provider).font(.caption).foregroundColor(.secondary)
            HStack {
                Button(tr("Read paper")) { if let work = store.importCitingWork(event) { store.openReader(work) } }
                Button(tr("Open paper")) { if let work = store.importCitingWork(event) { store.selectedCitationID = nil; store.showPaper(work.id) } }
                Menu(tr("Add to Project")) {
                    ForEach(store.database.projects) { project in Button(project.title) { if let work = store.importCitingWork(event) { store.change { db in if let i = db.objects.firstIndex(where: { $0.id == work.id }), !db.objects[i].projects.contains(project.id) { db.objects[i].projects.append(project.id) } } } } }
                    if store.database.projects.isEmpty { Button(tr("Create Project…")) { store.sheet = .project } }
                }
                if let url = event.citingWork.sources.first?.url { Link(tr("View source ↗"), destination: url) }
            }
            Divider(); SectionCaption(text: "Abstract")
            Text(event.citingWork.abstract.isEmpty ? tr("No abstract available.") : event.citingWork.abstract).lineSpacing(6).textSelection(.enabled)
            if let context = event.context { SectionCaption(text: "Provider citation context"); Text(context).textSelection(.enabled) }
            if let intent = event.intent { Text(tr("Provider citation intent") + ": " + intent + " · " + event.provider).font(.caption) }
        }
    }
}

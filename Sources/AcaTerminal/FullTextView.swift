import SwiftUI
import AcaCore
import AcaConnectors

struct FullTextView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("interfaceLanguage") private var language = "system"
    let paper: ResearchObject
    @State private var resolution = FullTextResolution(locations: [])
    @State private var loading = true
    @State private var downloading = false
    @State private var activeLocation: String?
    @State private var showServiceStatus = false
    @State private var failure = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(tr("Find full text")).font(.system(size: 25, design: .serif))
            Text(paper.title).font(.headline)
            if loading { ProgressView(tr("Looking for accessible versions…")) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(resolution.locations) { location in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(location.provider).font(.headline)
                                Text(tr(location.version.title) + " · " + tr(location.accessType == .openAccess ? "Open Access" : location.accessType == .local ? "Local" : location.accessType == .library ? "Library" : "Institutional access may be required")).font(.caption).foregroundColor(.secondary)
                                Text(location.url.host ?? tr("Local file")).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            if location.isDirectPDF { Button { read(location) } label: { HStack(spacing: 6) { if activeLocation == location.id { ProgressView().controlSize(.small) }; Text(tr(activeLocation == location.id ? "Opening…" : "Read paper")) } }.disabled(downloading) }
                            else { Link(tr("Open source ↗"), destination: location.url) }
                        }
                        Divider()
                    }
                    if !loading && resolution.locations.isEmpty { Text(tr("No accessible full text found. You can attach a local PDF.")).foregroundColor(.secondary) }
                    if !resolution.failures.isEmpty { AcaDisclosure(title: tr("Service status"), expanded: $showServiceStatus) { ForEach(resolution.failures, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) } } }
                }
            }.frame(maxHeight: 360)
            if !failure.isEmpty { Text(tr(failure)).font(.caption).foregroundColor(.secondary) }
            HStack { if downloading { ProgressView().controlSize(.small) }; Spacer(); Button(tr("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(30).frame(width: 560)
        .task {
            var providers: [FullTextProvider] = [LocalFullTextProvider(), ZoteroFullTextProvider(), OpenAlexProvider(apiKey: try? store.credentials.read("openalex.apiKey"), transport: store.httpClient), ArxivFullTextProvider(), PublisherFullTextProvider()]
            let email = UserDefaults.standard.string(forKey: "unpaywall.email") ?? ""
            if !email.isEmpty { providers.insert(UnpaywallFullTextProvider(email: email, transport: store.httpClient), at: 3) }
            resolution = await FullTextResolver().resolve(paper, providers: providers); loading = false
        }
    }
    func read(_ location: FullTextLocation) {
        guard !downloading else { return }; downloading = true; activeLocation = location.id; failure = ""
        Task {
            defer { downloading = false; activeLocation = nil }
            do {
                if location.accessType == .local || location.accessType == .library { dismiss(); store.openReader(paper, sourceID: location.sourceID); return }
                let url = try await FullTextDownload.download(location, directory: store.databaseURL.deletingLastPathComponent().appendingPathComponent("FullText"))
                if store.change({ db in
                    guard let index = db.objects.firstIndex(where: { $0.id == paper.id }) else { throw CoreError.invalid("Paper is no longer in the library.") }
                    db.objects[index].sources.append(.init(provider: "local-pdf", externalID: location.id, url: url, metadata: ["fullTextProvider": location.provider, "paperVersion": location.version.rawValue, "accessType": location.accessType.rawValue, "hostType": location.hostType ?? "", "sourceURL": location.url.absoluteString]))
                }), let updated = store.database.objects.first(where: { $0.id == paper.id }) { dismiss(); store.openReader(updated, sourceID: "local-pdf:" + location.id) }
            } catch { failure = error.localizedDescription }
        }
    }
}

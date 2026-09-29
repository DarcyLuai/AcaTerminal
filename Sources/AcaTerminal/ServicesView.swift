import SwiftUI
import AppKit
import AcaCore
import AcaConnectors

extension WorkspaceStore {
    func refreshMetrics(_ object: ResearchObject) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let provider = OpenAlexProvider(apiKey: try credentials.read("openalex.apiKey"), transport: httpClient)
            let (enriched, metrics) = try await provider.metrics(for: object)
            if change({ db in
                guard let i = db.objects.firstIndex(where: { $0.id == object.id }) else { return }
                db.objects[i] = ResearchObjectResolver().merge(enriched, into: db.objects[i])
                db.citationSnapshots.append(.init(objectID: object.id, metrics: metrics))
            }) { rebuildAnalytics(); message = "Citation snapshot saved from OpenAlex." }
        } catch { self.error = error.localizedDescription }
    }
    func lookupResearcher(_ orcid: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var profile = try await OpenAlexProvider(apiKey: credentials.read("openalex.apiKey"), transport: httpClient).researcher(orcid: orcid)
            if let current = database.identity, current.orcid == profile.orcid { profile.authenticated = current.authenticated }
            if change({ $0.adoptIdentity(profile) }) { rebuildAnalytics(); message = "OpenAlex profile snapshot saved. Identity verification is separate from public lookup." }
        } catch { self.error = error.localizedDescription }
    }
}
struct ServicesView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    var service: Destination
    @State private var local = true
    @AppStorage("zotero.userID") private var userID = ""
    @State private var apiKey = ""
    @State private var orcid = ""
    @State private var batch: LibraryImport?
    @State private var reviewImport = false
    @State private var oauth = false
    @State private var keySaved = false
    var body: some View {
        Page(title: tr(service.rawValue)) {
            switch service {
            case .zotero:
                RuleSection(title: tr("Library connection")) {
                    SettingsRow(title: tr("Import from")) {
                        ChoiceField(selection: Binding(get: { local ? "local" : "web" }, set: { local = $0 == "local" }), options: [("local", "Zotero on this Mac"), ("web", "Zotero Web API")])
                    }
                    if !local {
                        SettingsRow(title: tr("User ID")) { TextField(tr("Numeric Zotero user ID"), text: $userID).textFieldStyle(.roundedBorder) }
                        SettingsRow(title: tr("API key")) { SecureField(tr(keySaved ? "Saved in Keychain" : "API key"), text: $apiKey).textFieldStyle(.roundedBorder) }
                        SettingsRow(title: tr("Access")) { Link(tr("Create a read-only key"), destination: URL(string: "https://www.zotero.org/settings/keys/new")!) }
                    }
                }
                if local { Text(tr("Open Zotero and enable local API access in its advanced settings.")).font(.system(size: 13)).foregroundColor(.secondary) }
                HStack(spacing: 20) {
                    Button(tr(store.busy ? "Reading library…" : "Connect & Review Import")) { Task { await importZotero() } }.disabled(store.busy || (!local && userID.isEmpty))
                    if !local, keySaved { Button(tr("Remove saved key")) { do { try store.credentials.remove("zotero.apiKey"); keySaved = false; apiKey = "" } catch { store.error = error.localizedDescription } }.buttonStyle(.link) }
                }
            case .orcid:
                RuleSection(title: tr("Researcher identity")) {
                    if let identity = store.database.identity {
                        SettingsRow(title: tr("Name")) { Text(identity.name) }
                        SettingsRow(title: tr("Identity")) { Text(tr(identity.authenticated ? "Authenticated" : "Public profile · not authenticated")).font(.caption).foregroundColor(.secondary) }
                    }
                    SettingsRow(title: tr("ORCID iD")) { TextField(tr("0000-0000-0000-0000"), text: $orcid).textFieldStyle(.roundedBorder) }
                }
                Button(tr("Look Up in OpenAlex")) { Task { await store.lookupResearcher(orcid) } }.disabled(store.busy || orcid.isEmpty)
                RuleSection(title: tr("Authentication")) {
                    SettingsRow(title: tr("ORCID OAuth")) { RowAction(title: tr("Developer OAuth Setup…")) { oauth = true }.disabled(store.busy) }
                    if store.database.identity?.authenticated == true {
                        SettingsRow(title: tr("Connection")) { Button(tr("Disconnect ORCID")) {
                            do { try store.credentials.remove("orcid.accessToken"); store.change { $0.identity?.authenticated = false } } catch { store.error = error.localizedDescription }
                        } }
                    }
                }
            case .openalex:
                RuleSection(title: tr("Citation provider")) {
                    SettingsRow(title: tr("Provider")) { Text(tr("OpenAlex")) }
                    SettingsRow(title: tr("API key")) { SecureField(tr(keySaved ? "Saved in Keychain" : "API key"), text: $apiKey).textFieldStyle(.roundedBorder) }
                    SettingsRow(title: tr("Access")) { Link(tr("Get an API key"), destination: URL(string: "https://openalex.org/settings/api")!) }
                }
                HStack(spacing: 20) {
                    Button(tr("Save to Keychain")) { do { try store.credentials.write(apiKey, for: "openalex.apiKey"); apiKey = ""; keySaved = true } catch { store.error = error.localizedDescription } }.disabled(apiKey.isEmpty)
                    if keySaved { Button(tr("Remove saved key")) { do { try store.credentials.remove("openalex.apiKey"); keySaved = false } catch { store.error = error.localizedDescription } }.buttonStyle(.link) }
                }
            default: EmptyView()
            }
        }.onAppear { keySaved = ((try? store.credentials.read(service == .zotero ? "zotero.apiKey" : "openalex.apiKey")) ?? nil) != nil; orcid = store.database.identity?.orcid ?? "" }
        .sheet(isPresented: $reviewImport) { if let batch = batch { ImportReviewView(batch: batch) } }
        .sheet(isPresented: $oauth) { OAuthSetupView() }
    }
    var subtitle: String { service == .zotero ? "Your library provider. Your research stays yours." : service == .orcid ? "A persistent identity for your research." : "An open view of scholarly impact." }
    func importZotero() async {
        guard !store.busy else { return }; store.busy = true; defer { store.busy = false }
        do {
            if !local && !apiKey.isEmpty { try store.credentials.write(apiKey, for: "zotero.apiKey"); apiKey = ""; keySaved = true }
            let connector = try ZoteroProvider(local: local, userID: userID, apiKey: local ? nil : store.credentials.read("zotero.apiKey"), transport: store.httpClient)
            batch = try await connector.importLibrary(); reviewImport = true
        } catch { store.error = error.localizedDescription }
    }
}
struct ImportReviewView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    let batch: LibraryImport
    @State private var decisions: [UUID: ImportDecision] = [:]
    private var ambiguous: [ResearchObject] { var staged = store.database.objects; var result: [ResearchObject] = []; for item in batch.objects { switch ResearchObjectResolver().resolve(item, in: staged) { case .possible: result.append(item); case .new: staged.append(item); case .match: break } }; return result }
    var body: some View {
        EditorFrame(title: tr("Review Zotero Import"), saveTitle: tr("Import"), valid: ambiguous.allSatisfy { decisions[$0.id] != nil }, save: {
            if store.change({ try $0.apply(batch, decisions: decisions) }) { store.message = "Imported \(batch.objects.count) source records, \(batch.notes.count) notes and \(batch.collections.count) collections. Exact matches were merged."; store.destination = .library; dismiss() }
        }) {
            Text(trf("%d items · %d notes · %d collections", batch.objects.count, batch.notes.count, batch.collections.count)).foregroundColor(.secondary)
            Text(tr("Exact identifiers merge automatically. Possible title matches need your decision.")).font(.caption)
            if ambiguous.isEmpty { Text(tr("No ambiguous identities found.")).padding(.vertical, 15) }
            else { ScrollView { VStack(alignment: .leading, spacing: 22) { ForEach(ambiguous) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.headline)
                    Picker(tr("Resolve"), selection: Binding(get: { choice(item.id) }, set: { decisions[item.id] = $0 == "new" ? .separate : UUID(uuidString: $0).map(ImportDecision.merge) })) {
                        Text(tr("Choose…")).tag(""); Text(tr("Keep as a separate work")).tag("new")
                        ForEach(candidates(item)) { old in Text(tr("Merge: ") + old.title + " · " + (old.doi ?? "no DOI")).tag(old.id.uuidString) }
                    }
                }
            } } }.frame(height: 300) }
        }
    }
    func candidates(_ item: ResearchObject) -> [ResearchObject] {
        let pool = store.database.objects + Array(batch.objects.prefix { $0.id != item.id })
        if case .possible(let ids) = ResearchObjectResolver().resolve(item, in: pool) { return pool.filter { ids.contains($0.id) } }; return []
    }
    func choice(_ id: UUID) -> String { switch decisions[id] { case .merge(let target): return target.uuidString; case .separate: return "new"; case nil: return "" } }
}
struct OAuthSetupView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State private var clientID = ""; @State private var secret = ""; @State private var redirect = "https://localhost/"; @State private var callback = ""
    @State private var authorization: ORCIDAuthorization?
    @State private var working = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("ORCID Developer Authorization")).font(.system(size: 24, design: .serif))
            Text(tr("Use your own registered Public API client. This setup is for development; a shared application secret must never be distributed with AcaTerminal.")).font(.caption).foregroundColor(.secondary)
            TextField(tr("Client ID"), text: $clientID); SecureField(tr("Personal client secret (not your ORCID password)"), text: $secret); TextField(tr("Registered HTTPS redirect URI"), text: $redirect)
            Button(tr("Open Official ORCID Authorization")) {
                do { guard let url = URL(string: redirect) else { throw CoreError.invalid("Enter a registered HTTPS redirect URI.") }; let flow = try ORCIDAuthorization(clientID: clientID, redirectURI: url)
                    try store.credentials.write(secret, for: "orcid.personalClientSecret"); secret = ""; authorization = flow; NSWorkspace.shared.open(flow.url)
                } catch { store.error = error.localizedDescription }
            }.disabled(clientID.isEmpty || secret.isEmpty || working)
            if authorization != nil {
                Text(tr("After authorizing in your browser, paste the complete redirect URL below. A localhost redirect may show an unavailable page; copy its address without bypassing any browser warning. The callback state is checked and expires after 10 minutes.")).font(.caption).foregroundColor(.secondary)
                SecureField(tr("Full callback URL"), text: $callback)
                Button(tr(working ? "Exchanging authorization…" : "Complete Authorization")) { Task { await finish() } }.disabled(callback.isEmpty || working)
            }
            Divider(); HStack { Button(tr("Remove developer secret")) { do { try store.credentials.remove("orcid.personalClientSecret"); secret = "" } catch { store.error = error.localizedDescription } }; Spacer(); Button(tr("Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working) }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 550)
    }
    func finish() async {
        guard !working, let flow = authorization, let url = URL(string: callback) else { return }; working = true; store.busy = true; defer { working = false; store.busy = false }; authorization = nil; callback = ""
        do { guard let secret = try store.credentials.read("orcid.personalClientSecret") else { throw CoreError.invalid("The personal client secret is missing from Keychain.") }
            var profile = try await ORCIDOAuthClient(transport: store.httpClient).exchange(flow, callback: url, personalClientSecret: secret, credentials: store.credentials)
            if let current = store.database.identity, current.orcid == profile.orcid { profile.metrics = current.metrics; profile.works = current.works }
            if store.change({ $0.identity = profile }) { store.message = "ORCID identity authenticated. Token stored in Keychain."; dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

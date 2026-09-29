import SwiftUI
import AcaCore
import AcaConnectors
struct SubmissionsView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @State private var updating = false
    @State private var editing = false
    @State private var refreshing = false
    var selected: Submission? { store.database.submissions.first { $0.id == store.selectedSubmission } }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack { Text(tr("Submissions")).font(.system(size: 25, design: .serif)); Spacer(); Button { store.sheet = .submission } label: { Image(systemName: "plus") }.accessibilityLabel(tr("Add submission")) }.padding(22)
                List(store.database.submissions.sorted { $0.updatedAt > $1.updatedAt }, selection: $store.selectedSubmission) { submission in
                    VStack(alignment: .leading, spacing: 9) { Text(submission.title).font(.system(size: 15, weight: .medium)); Text(submission.journal).font(.caption).foregroundColor(.secondary); Text(tr(submission.status.title)).font(.caption).foregroundColor(Palette.accent) }.padding(.vertical, 12).tag(submission.id)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }.frame(minWidth: 255, idealWidth: 280, maxWidth: 340)
            if let submission = selected {
                Page(title: submission.title, subtitle: submission.journal) {
                    HStack { Label(tr(submission.status.title), systemImage: "circle.dotted").font(.system(size: 19)); Spacer(); Button(tr("Refresh from URL")) { refresh(submission) }.disabled(refreshing || submission.portalURL == nil); Button(tr("Supplement details…")) { editing = true }; Button(tr("Update Status…")) { updating = true } }
                    Text(tr("Raw status") + " · " + (submission.statusRaw.isEmpty ? tr("Not supplied") : submission.statusRaw)).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                    HStack { Text(tr(submission.submissionDateUnknown == true ? "Added" : "Submitted") + " · " + submission.submittedAt.formatted(.dateTime.locale(L10n.locale).year().month().day())); Spacer(); Text(tr(submission.source == "openreview" ? "OpenReview" : "Manual tracking")) }.font(.caption).foregroundColor(.secondary)
                    if !submission.externalManuscriptID.isEmpty { Text(tr("Manuscript ID") + " · " + submission.externalManuscriptID).font(.caption).textSelection(.enabled) }
                    if let url = submission.portalURL, url.scheme == "https" {
                        HStack { Text((try? SubmissionLink.parse(url.absoluteString).platform) ?? tr("Website")).font(.caption).foregroundColor(.secondary); Spacer(); Link(tr("Open journal portal ↗"), destination: url) }
                        if submission.status == .unknown { Text(tr("No readable status yet. Open the portal to check, or supplement the details.")).font(.caption).foregroundColor(.secondary) }
                    }
                    if let id = submission.manuscriptID, let manuscript = store.database.objects.first(where: { $0.id == id }) { Button(tr("Manuscript: ") + manuscript.title) { store.showPaper(id) }.buttonStyle(.link) }
                    Divider()
                    SectionCaption(text: "Status timeline")
                    ForEach(submission.history.reversed()) { event in
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(Palette.accent).padding(.top, 8)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(tr(event.status.title)).font(.system(size: 16, weight: .medium)); Spacer(); Text(event.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundColor(.secondary) }
                                Text(event.statusRaw.isEmpty ? tr("No original status supplied") : event.statusRaw).font(.system(size: 13)).foregroundColor(.secondary).textSelection(.enabled)
                                Text(tr(event.source.capitalized)).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }.padding(.bottom, 12)
                    }
                }.sheet(isPresented: $updating) { StatusUpdateEditor(submission: submission) }.sheet(isPresented: $editing) { SubmissionEditor(existing: submission) }
            } else { EmptyPage(title: tr("Follow the next chapter"), detail: tr("Add a submission and keep its original status, normalized stage and history together."), icon: "paperplane") }
        }
    }
    func refresh(_ submission: Submission) {
        guard let url = submission.portalURL else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let result = try await SubmissionLinkProvider(transport: store.httpClient).lookup(url.absoluteString)
                if let raw = result.statusRaw, let status = result.status {
                    store.change { db in
                        guard let i = db.submissions.firstIndex(where: { $0.id == submission.id }), db.submissions[i].portalURL == url else { return }
                        db.submissions[i].source = result.statusSource
                        try db.submissions[i].record(status: status, raw: raw)
                    }
                }
                store.message = tr(result.notice)
            } catch { store.error = tr(error.localizedDescription) }
        }
    }
}
struct SubmissionEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var existing: Submission? = nil
    @State private var title = ""; @State private var journal = ""; @State private var externalID = ""; @State private var portal = ""; @State private var raw = ""
    @State private var date = Date(); @State private var hasDate = false
    @State private var status = SubmissionStatus.unknown
    @State private var manuscriptID: UUID?
    @State private var recognized: SubmissionLinkResult?
    @State private var lookedUpURL = ""
    @State private var fetching = false
    @State private var showDetails = false
    @State private var notice = ""
    var link: SubmissionLink? { try? SubmissionLink.parse(portal) }
    var valid: Bool { !fetching && (link != nil || (!title.isEmpty && !journal.isEmpty && portal.isEmpty)) }
    var body: some View {
        EditorFrame(title: tr(existing == nil ? "Add Submission" : "Supplement details…"), saveTitle: tr(existing == nil ? "Add Submission" : "Save"), valid: valid, save: save) {
            TextField(tr("Journal portal URL (https://…)"), text: $portal).onChange(of: portal) { _ in recognized = nil; notice = "" }
            HStack {
                Text(link?.platform ?? tr("Start with a submission URL")).foregroundColor(.secondary)
                Spacer()
                if fetching { ProgressView().controlSize(.small) }
                Button(tr("Read from URL")) { lookup() }.disabled(link == nil || fetching)
            }
            if !notice.isEmpty { Text(tr(notice)).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
            AcaDisclosure(title: tr("Supplement details (optional)"), expanded: $showDetails) {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(tr("Manuscript title (optional)"), text: $title)
                    TextField(tr("Journal (optional)"), text: $journal)
                    TextField(tr("Journal manuscript ID (optional)"), text: $externalID)
                    Picker(tr("Link manuscript"), selection: $manuscriptID) {
                        Text(tr("None")).tag(nil as UUID?)
                        ForEach(store.database.objects.filter { $0.type == .manuscript }) { Text($0.title).tag(Optional($0.id)) }
                    }.onChange(of: manuscriptID) { id in if title.isEmpty { title = store.database.objects.first { $0.id == id }?.title ?? "" } }
                    if existing == nil || existing?.submissionDateUnknown == true {
                        Toggle(tr("I know the submission date"), isOn: $hasDate)
                        if hasDate { DatePicker(tr("Submitted"), selection: $date, in: ...(existing?.history.first?.date ?? Date()), displayedComponents: [.date]) }
                    }
                    TextField(tr("Original status text (optional)"), text: $raw)
                    Picker(tr("Normalized status"), selection: $status) { ForEach(SubmissionStatus.allCases, id: \.self) { Text(tr($0.title)).tag($0) } }
                }.padding(.top, 14)
            }
        }.onAppear {
            if let item = existing { title = item.title; journal = item.journal; externalID = item.externalManuscriptID; portal = item.portalURL?.absoluteString ?? ""; raw = item.statusRaw; status = item.status; date = item.submittedAt; hasDate = item.submissionDateUnknown != true; manuscriptID = item.manuscriptID; showDetails = true }
        }
    }
    func lookup(saveAfter: Bool = false) {
        guard link != nil, !fetching else { return }
        let url = portal
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let result = try await SubmissionLinkProvider(transport: store.httpClient).lookup(url)
                guard portal == url else { return }
                recognized = result; lookedUpURL = url; notice = result.notice
                if title.isEmpty { title = result.title ?? "" }; if journal.isEmpty { journal = result.journal ?? "" }; if externalID.isEmpty { externalID = result.externalID ?? "" }
                if raw.isEmpty, let value = result.statusRaw { raw = value; status = result.status ?? .unknown }
                showDetails = true
                if saveAfter { commit() }
            } catch { guard portal == url else { return }; notice = error.localizedDescription; lookedUpURL = url; showDetails = true }
        }
    }
    func save() { if link != nil && lookedUpURL != portal && existing == nil { lookup(saveAfter: true) } else { commit() } }
    func commit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanJournal = journal.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusSource = recognized?.statusRaw == raw && recognized?.status == status ? "openreview" : "manual"
        let effectiveStatus = status == .unknown && !raw.isEmpty ? SubmissionStatus.normalize(raw) : status
        if let existing = existing {
            if store.change({ db in
                guard let i = db.submissions.firstIndex(where: { $0.id == existing.id }) else { return }
                if !cleanTitle.isEmpty { db.submissions[i].title = cleanTitle }; if !cleanJournal.isEmpty { db.submissions[i].journal = cleanJournal }
                db.submissions[i].portalURL = link?.url; db.submissions[i].externalManuscriptID = externalID
                db.submissions[i].manuscriptID = manuscriptID
                if existing.submissionDateUnknown == true, hasDate { db.submissions[i].submittedAt = min(date, existing.history.first?.date ?? date); db.submissions[i].submissionDateUnknown = false }
                if raw != existing.statusRaw || effectiveStatus != existing.status { db.submissions[i].source = statusSource }
                try db.submissions[i].record(status: effectiveStatus, raw: raw)
            }) { dismiss() }
        } else {
            var item = Submission(title: cleanTitle.isEmpty ? tr("Untitled submission") : cleanTitle, journal: cleanJournal.isEmpty ? (link?.url.host ?? "") : cleanJournal, externalManuscriptID: externalID, submittedAt: hasDate ? date : Date(), status: .unknown, statusRaw: "", portalURL: link?.url, source: statusSource)
            item.submissionDateUnknown = !hasDate; item.manuscriptID = manuscriptID
            do {
                _ = try item.record(status: effectiveStatus, raw: raw)
                if store.change({ $0.submissions.append(item) }) { store.showSubmission(item.id); dismiss() }
            } catch { store.error = error.localizedDescription }
        }
    }
}

struct StatusUpdateEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var submission: Submission
    @State private var status: SubmissionStatus = .unknown
    @State private var raw = ""
    @State private var date = Date()
    var body: some View { EditorFrame(title: tr("Update Submission Status"), valid: !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: {
        if store.change({ db in guard let i = db.submissions.firstIndex(where: { $0.id == submission.id }) else { throw CoreError.invalid("Submission no longer exists.") }; db.submissions[i].source = "manual"; try db.submissions[i].record(status: status, raw: raw, at: date) }) { dismiss() }
    }) {
        Text(submission.title).foregroundColor(.secondary)
        TextField(tr("Original journal status"), text: $raw)
        HStack { Picker(tr("Normalized status"), selection: $status) { ForEach(SubmissionStatus.allCases, id: \.self) { Text(tr($0.title)).tag($0) } }; Button(tr("Suggest")) { status = .normalize(raw) } }
        DatePicker(tr("Effective date"), selection: $date, in: (submission.history.last?.date ?? submission.submittedAt)...max(submission.history.last?.date ?? submission.submittedAt, Date()), displayedComponents: [.date, .hourAndMinute])
        Text(tr("An unchanged status will not create a duplicate timeline event.")).font(.caption).foregroundColor(.secondary)
    }.onAppear { status = submission.status; raw = submission.statusRaw }
    }
}

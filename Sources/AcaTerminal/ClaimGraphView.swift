import SwiftUI
import AcaCore

struct ClaimGraphView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    var project: ResearchProject
    @State private var graph = ClaimGraph(database: ResearchDatabase(), projectID: UUID())
    @State private var selected: UUID?
    @State private var search = ""
    @State private var zoom: CGFloat = 0.8
    @State private var camera = CGSize(width: 30, height: 25)
    @GestureState private var drag = CGSize.zero
    @State private var linking = false
    @State private var focused = false
    var visible: [ClaimGraph.Node] { guard focused, let selected = selected else { return graph.nodes }; let ids = graph.neighborhood(selected); return graph.nodes.filter { ids.contains($0.id) } }
    var positions: [UUID: CGPoint] {
        var rows: [String: Int] = [:], result: [UUID: CGPoint] = [:]
        for node in visible {
            let col = node.kind == .claim ? 0 : node.kind == .evidence ? 1 : 2
            let row = rows[node.kind.rawValue, default: 0]; rows[node.kind.rawValue] = row + 1
            result[node.id] = CGPoint(x: 140 + col * 320, y: 65 + row * 140)
        }
        return result
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(tr("Search graph…"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                if !search.isEmpty { Menu(tr("Matches")) { ForEach(graph.search(search)) { node in Button(String(node.text.prefix(80))) { select(node.id, center: true) } } }.frame(maxWidth: 120) }
                Spacer()
                Button { zoom = max(0.3, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel(tr("Zoom out"))
                Text("\(Int(zoom * 100))%").font(.caption).monospacedDigit().frame(width: 42)
                Button { zoom = min(1.6, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel(tr("Zoom in"))
                if selected != nil { Button(tr(focused ? "Show all" : "Focus selected")) { focused.toggle(); camera = CGSize(width: 30, height: 25) } }
                Button(tr("Add relationship")) { linking = true }.disabled(graph.nodes.filter { $0.kind == .claim }.count < 2)
            }.padding(18)
            Divider()
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    let points = positions
                    ZStack(alignment: .topLeading) {
                        Color.primary.opacity(0.015)
                        Canvas { context, _ in
                            for edge in graph.edges {
                                guard let source = points[edge.source], let target = points[edge.target] else { continue }
                                let a = CGPoint(x: source.x * zoom + camera.width + drag.width, y: source.y * zoom + camera.height + drag.height)
                                let b = CGPoint(x: target.x * zoom + camera.width + drag.width, y: target.y * zoom + camera.height + drag.height)
                                let sameColumn = source.x == target.x
                                let control = CGPoint(x: sameColumn ? min(a.x, b.x) - 100 * zoom : (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                var path = Path(); path.move(to: a); path.addQuadCurve(to: b, control: control)
                                context.stroke(path, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: edge.label == "contradicts" ? [4, 3] : []))
                                let t: CGFloat = 0.54
                                let tip = CGPoint(x: (1-t)*(1-t)*a.x + 2*(1-t)*t*control.x + t*t*b.x, y: (1-t)*(1-t)*a.y + 2*(1-t)*t*control.y + t*t*b.y)
                                let angle = atan2((1-t)*(control.y-a.y)+t*(b.y-control.y), (1-t)*(control.x-a.x)+t*(b.x-control.x))
                                var arrow = Path(); arrow.move(to: CGPoint(x: tip.x-7*cos(angle-0.45), y: tip.y-7*sin(angle-0.45))); arrow.addLine(to: tip); arrow.addLine(to: CGPoint(x: tip.x-7*cos(angle+0.45), y: tip.y-7*sin(angle+0.45)))
                                context.stroke(arrow, with: .color(.secondary), lineWidth: 1)
                                if edge.label != "source" { context.draw(Text(tr(edge.label)).font(.system(size: 10)).foregroundColor(.secondary), at: control) }
                            }
                        }.allowsHitTesting(false)
                        ForEach(visible) { node in
                            if let p = points[node.id] {
                                Button { select(node.id) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(tr(node.kind.rawValue.capitalized)).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                        Text(node.text).font(.system(size: 13, design: node.kind == .claim ? .serif : .default)).lineLimit(3).multilineTextAlignment(.leading)
                                    }.frame(width: 218, height: 76, alignment: .topLeading).padding(10)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                }.buttonStyle(AcaButtonStyle(inset: 0, selected: selected == node.id))
                                    .accessibilityLabel(tr(node.kind.rawValue.capitalized) + ": " + node.text)
                                    .overlay(Rectangle().stroke(Palette.accent.opacity(!search.isEmpty && node.text.localizedCaseInsensitiveContains(search) ? 0.7 : 0.16), lineWidth: 1).allowsHitTesting(false))
                                    .scaleEffect(zoom).position(x: p.x * zoom + camera.width + drag.width, y: p.y * zoom + camera.height + drag.height)
                            }
                        }
                        if graph.nodes.isEmpty { Text(tr("Add claims and evidence to see their connections.")).foregroundColor(.secondary).frame(width: geometry.size.width, height: geometry.size.height) }
                    }.contentShape(Rectangle()).clipped()
                        .gesture(DragGesture(minimumDistance: 4).updating($drag) { value, state, _ in state = value.translation }.onEnded { camera.width += $0.translation.width; camera.height += $0.translation.height })
                        .help(tr("Claim graph. Drag to pan; use zoom controls to resize."))
                }
                if selected != nil { Divider(); inspector.frame(width: 250).transition(.opacity) }
            }
            HStack { Text(tr("Drag to pan · arrows point from source to target")); Spacer(); Text("\(graph.nodes.count) " + tr("nodes")) }.font(.caption).foregroundColor(.secondary).padding(12)
        }.sheet(isPresented: $linking) { ClaimRelationEditor(project: project) }
            .task(id: project.id.uuidString + String(store.databaseRevision)) { let snapshot = store.database, id = project.id; let next = await Task.detached(priority: .userInitiated) { ClaimGraph(database: snapshot, projectID: id) }.value; if !Task.isCancelled { graph = next } }
    }
    func select(_ id: UUID, center: Bool = false) {
        withAnimation(AcaMotion.panels(reduced: reduced)) { selected = id }
        if center, let p = positions[id] { withAnimation(AcaMotion.panels(reduced: reduced)) { camera = CGSize(width: 180 - p.x * zoom, height: 150 - p.y * zoom) } }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let node = graph.nodes.first(where: { $0.id == selected }) {
                    HStack { SectionCaption(text: node.kind.rawValue.capitalized); Spacer(); Button { withAnimation(AcaMotion.panels(reduced: reduced)) { selected = nil; focused = false } } label: { Image(systemName: "xmark") }.buttonStyle(AcaButtonStyle()).accessibilityLabel(tr("Close Inspector")) }
                    Text(node.text).font(.system(size: 17, design: .serif)).textSelection(.enabled)
                    if let claim = store.database.claims.first(where: { $0.id == node.id }) {
                        let evidence = store.database.evidence.filter { claim.evidence.contains($0.id) }
                        ForEach(EvidenceRelationship.allCases, id: \.self) { kind in HStack { Text(tr(kind.rawValue.capitalized)); Spacer(); Text("\(evidence.filter { store.database.relationship(evidenceID: $0.id, claimID: claim.id) == kind }.count)") }.font(.caption) }
                        SectionCaption(text: "Evidence")
                        ForEach(evidence) { item in Button { select(item.id) } label: { Text(item.quote.isEmpty ? item.note : item.quote).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(AcaButtonStyle()) }
                        SectionCaption(text: "Related claims")
                        ForEach((store.database.claimRelations ?? []).filter { $0.sourceClaimID == claim.id || $0.targetClaimID == claim.id }) { relation in
                            let outgoing = relation.sourceClaimID == claim.id
                            let other = outgoing ? relation.targetClaimID : relation.sourceClaimID
                            Button { select(other, center: true) } label: { VStack(alignment: .leading, spacing: 6) { Text((outgoing ? "→ " : "← ") + tr(relation.relationship.rawValue)).font(.caption).foregroundColor(.secondary); Text(store.database.claims.first { $0.id == other }?.text ?? "").lineLimit(3) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(AcaButtonStyle())
                                .contextMenu { Button(tr("Remove relationship")) { store.change { $0.claimRelations?.removeAll { $0.id == relation.id } } } }
                        }
                    }
                    if let item = store.database.evidence.first(where: { $0.id == node.id }) {
                        Text(pageLabel(item.page)).font(.caption).foregroundColor(.secondary)
                        Text(store.database.objects.first { $0.id == item.paperID }?.title ?? "").font(.caption)
                        Button(tr("Open Source")) { store.openEvidence(item) }
                    }
                    if let item = store.database.objects.first(where: { $0.id == node.id }) { Button(tr("Open Reader")) { store.openReader(item) } }
                } else { Text(tr("Select a claim, evidence or paper.")).foregroundColor(.secondary) }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct ClaimRelationEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var project: ResearchProject
    @State private var source: UUID?
    @State private var target: UUID?
    @State private var kind = ClaimRelationship.supports
    var body: some View {
        EditorFrame(title: tr("Add relationship"), valid: source != nil && target != nil && source != target, save: {
            if let a = source, let b = target, store.change({ try $0.addClaimRelation(.init(projectID: project.id, sourceClaimID: a, targetClaimID: b, relationship: kind)) }) { dismiss() }
        }) {
            Picker(tr("Source claim"), selection: $source) { Text(tr("Choose a claim")).tag(nil as UUID?); ForEach(store.database.claims.filter { $0.projectID == project.id }) { Text($0.text).tag(Optional($0.id)) } }
            Picker(tr("Relationship"), selection: $kind) { ForEach(ClaimRelationship.allCases, id: \.self) { Text(tr($0.rawValue)).tag($0) } }
            Picker(tr("Target claim"), selection: $target) { Text(tr("Choose a claim")).tag(nil as UUID?); ForEach(store.database.claims.filter { $0.projectID == project.id }) { Text($0.text).tag(Optional($0.id)) } }
            Text(tr("The arrow points from the source claim to the target claim.")).font(.caption).foregroundColor(.secondary)
        }
    }
}

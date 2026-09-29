import SwiftUI

/// Shared feedback for custom controls. Native bordered buttons keep the system style.
struct AcaButtonStyle: ButtonStyle {
    var inset: CGFloat = 7
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration, inset: inset, selected: selected)
    }
    private struct Feedback: View {
        let configuration: Configuration
        let inset: CGFloat
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduced
        @State private var hovering = false
        var body: some View {
            configuration.label.padding(inset).frame(minHeight: 30)
                .contentShape(Rectangle())
                .background(Color.primary.opacity(enabled ? (configuration.isPressed ? 0.14 : selected ? 0.095 : hovering ? 0.055 : 0) : 0), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(selected ? 0.12 : 0), lineWidth: 1).allowsHitTesting(false))
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .animation(AcaMotion.feedback(reduced: reduced), value: hovering)
                .animation(AcaMotion.transition(reduced: reduced), value: selected)
                // Mouse-down is immediate; only release settles gently.
                .animation(configuration.isPressed ? nil : AcaMotion.feedback(reduced: reduced), value: configuration.isPressed)
        }
    }
}

struct DisclosureHeader: View {
    var title: String
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(AcaMotion.panels(reduced: reduced)) { expanded.toggle() } } label: {
            HStack(spacing: 12) {
                Text(tr(title)).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 16)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0)).accessibilityHidden(true)
            }.foregroundColor(.secondary).padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 38).contentShape(Rectangle())
        }.buttonStyle(AcaButtonStyle(inset: 0))
            .accessibilityLabel(tr(title)).accessibilityValue(tr(expanded ? "Expanded" : "Collapsed"))
    }
}
struct RuleSection<Content: View>: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var title: String
    var collapsible = false
    @ViewBuilder var content: Content
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsible { DisclosureHeader(title: title, expanded: $expanded).padding(.bottom, 7) }
            else { Text(tr(title)).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).padding(.bottom, 14) }
            Divider()
            if !collapsible || expanded { content.transition(.opacity) }
        }.clipped()
    }
}
struct AcaDisclosure<Content: View>: View {
    var title: String
    @Binding var expanded: Bool
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureHeader(title: title, expanded: $expanded)
            if expanded { content.padding(.top, 12).transition(.opacity) }
        }.clipped()
    }
}
struct SettingsRow<Content: View>: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 26) {
                Text(tr(title)).foregroundColor(.secondary).frame(width: 172, alignment: .leading)
                content.frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: 14)).frame(minHeight: 62).padding(.vertical, 4)
            Divider().opacity(0.65)
        }
    }
}
/// One control owns the full row; there is no nested checkbox competing for clicks.
struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        VStack(spacing: 0) {
            Button { isOn.toggle() } label: {
                HStack {
                    Text(tr(title)).foregroundColor(.secondary)
                    Spacer(minLength: 26)
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17)).foregroundColor(isOn ? .primary : .secondary).accessibilityHidden(true)
                }.font(.system(size: 14)).padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 70).contentShape(Rectangle())
            }.buttonStyle(AcaButtonStyle(inset: 0))
                .accessibilityLabel(tr(title)).accessibilityValue(tr(isOn ? "On" : "Off"))
            Divider().opacity(0.65)
        }
    }
}
struct ChoiceField: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @Binding var selection: String
    var options: [(String, String)]
    var body: some View { NativeChoiceField(selection: $selection, options: options.map { ($0.0, tr($0.1)) }).frame(height: 42) }
}
/// AppKit owns the complete popup bounds, including whitespace and the trailing arrow.
private struct NativeChoiceField: NSViewRepresentable {
    @Binding var selection: String
    var options: [(String, String)]
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded; button.controlSize = .large
        button.font = .systemFont(ofSize: 14); button.autoenablesItems = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator; button.action = #selector(Coordinator.select(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection; context.coordinator.ids = options.map(\.0)
        let titles = options.map(\.1)
        if button.itemTitles != titles { button.removeAllItems(); button.addItems(withTitles: titles) }
        if let index = options.firstIndex(where: { $0.0 == selection }) { button.selectItem(at: index) }
        button.isEnabled = enabled
    }
    final class Coordinator: NSObject {
        var selection: Binding<String>; var ids: [String] = []
        init(selection: Binding<String>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) { guard ids.indices.contains(sender.indexOfSelectedItem) else { return }; selection.wrappedValue = ids[sender.indexOfSelectedItem] }
    }
}
struct RowAction: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var title: String; var action: () -> Void
    var body: some View { Button(action: action) { HStack { Text(tr(title)); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary) }.padding(.horizontal, 15).frame(height: 42).contentShape(Rectangle()).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10), lineWidth: 1).allowsHitTesting(false)) }.buttonStyle(AcaButtonStyle(inset: 0)) }
}
struct ThemeOptions: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 0) {
            ForEach([("system", "System"), ("light", "Light"), ("comfort", "Eye Comfort"), ("dark", "Dark")], id: \.0) { option in
                Button { selection = option.0 } label: {
                    Text(tr(option.1)).frame(maxWidth: .infinity).frame(height: 40).contentShape(Rectangle())
                }.buttonStyle(AcaButtonStyle(inset: 0, selected: selection == option.0))
                    .accessibilityIdentifier("theme." + option.0)
                    .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10), lineWidth: 1).allowsHitTesting(false))
    }
}

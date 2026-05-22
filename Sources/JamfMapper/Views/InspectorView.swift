import JamfMapperCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            if let node = state.selectedNode {
                VStack(alignment: .leading, spacing: 16) {
                    InspectorHero(node: node) {
                        state.openSelectedNodeInJamf()
                    }

                    MetadataPanel(node: node)

                    if let source = scriptSource(for: node), !source.isEmpty {
                        ScriptSourcePanel(title: sourceTitle(for: node), source: source)
                    }

                    let sections = state.selectedDependencySections
                    RelationshipMapPanel(node: node, sections: sections) { item in
                        state.showingAuditReports = false
                        state.selectedObjectKind = item.node.objectType
                        state.selectedNodeKey = item.node.key
                    }

                    let nodeFindings = state.findings.filter { $0.nodeKey == node.key }
                    if !nodeFindings.isEmpty {
                        FindingSection(findings: nodeFindings)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyStateView(title: "No Selection", systemImage: "sidebar.right", detail: "Select an object to inspect its mappings.")
                    .padding()
            }
        }
    }

    private func scriptSource(for node: GraphNode) -> String? {
        if let source = node.metadata["scriptSource"] {
            return source
        }

        guard node.objectType == .extensionAttribute else { return nil }
        return state.graph.edges
            .first { $0.fromKey == node.key && $0.kind == .usesScript }
            .flatMap { state.node(for: $0.toKey)?.metadata["scriptSource"] }
    }

    private func sourceTitle(for node: GraphNode) -> String {
        if node.objectType == .extensionAttribute {
            "Extension Attribute Script"
        } else if node.metadata["sourceEAName"] != nil {
            "Embedded EA Script"
        } else {
            "Script Source"
        }
    }
}

private struct InspectorHero: View {
    let node: GraphNode
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: node.objectType.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(node.objectType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(node.name)
                        .font(.title2.bold())
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(action: onOpen) {
                    Label("Open in Jamf Pro", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            HStack(spacing: 8) {
                IdentityChip(title: "ID", value: node.objectId, systemImage: "number")
                if node.objectType.supportsEnabledState || node.metadata["unresolved"] == "true" {
                    StatusBadge(isEnabled: node.isEnabled, isApplicable: node.objectType.supportsEnabledState, isUnresolved: node.metadata["unresolved"] == "true")
                }
                if node.objectType.supportsScopeCount {
                    IdentityChip(title: "Scope", value: node.scopeCount.map(String.init) ?? "Unknown", systemImage: "scope")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct MetadataPanel: View {
    let node: GraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Object Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                row("Type", node.objectType.rawValue)
                row("Category", node.category ?? "None")
                row("Source", node.source.rawValue)
                if let sourceEAName = node.metadata["sourceEAName"] {
                    row("Source EA", sourceEAName)
                }
                row("Key", node.key)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct ScriptSourcePanel: View {
    let title: String
    let source: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView([.horizontal, .vertical]) {
                Text(source)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 140, maxHeight: 280)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "curlybraces")
                    .foregroundStyle(.purple)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(isExpanded ? "Hide source preview" : "Show source preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct RelationshipMapPanel: View {
    let node: GraphNode
    let sections: [DependencySection]
    var onSelect: (DependencyItem) -> Void

    private var outgoingCount: Int {
        sections.filter { $0.title != "Mapped To / Used By" }.reduce(0) { $0 + $1.items.count }
    }

    private var incomingCount: Int {
        sections.first { $0.title == "Mapped To / Used By" }?.items.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Dependency Mapping", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text("\(sections.reduce(0) { $0 + $1.items.count }) mapped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MappingOverview(node: node, outgoingCount: outgoingCount, incomingCount: incomingCount)

            if sections.isEmpty {
                EmptyRelationshipView()
            } else {
                VStack(spacing: 10) {
                    ForEach(sections) { section in
                        RelationshipSection(section: section, onSelect: onSelect)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct MappingOverview: View {
    let node: GraphNode
    let outgoingCount: Int
    let incomingCount: Int

    var body: some View {
        HStack(spacing: 8) {
            MappingMetric(title: "Depends On", count: outgoingCount, systemImage: "arrow.down.right.and.arrow.up.left", tint: .blue)

            VStack(spacing: 6) {
                Image(systemName: node.objectType.symbolName)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.teal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Selected")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 74)

            MappingMetric(title: "Used By", count: incomingCount, systemImage: "arrow.up.left.and.arrow.down.right", tint: .orange)
        }
    }
}

private struct MappingMetric: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RelationshipSection: View {
    let section: DependencySection
    var onSelect: (DependencyItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sectionIcon)
                    .foregroundStyle(sectionTint)
                    .frame(width: 18)
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(section.items.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sectionTint.opacity(0.14), in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(section.items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        RelationshipRow(item: item, tint: sectionTint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sectionIcon: String {
        switch section.title {
        case "Mapped To / Used By": "arrowshape.turn.up.left"
        case "Associated Groups": "person.3"
        case "Scripts": "terminal"
        case "Packages": "shippingbox"
        case "Extension Attributes", "Extension Attributes Used By Associated Groups": "tag"
        default: "point.3.connected.trianglepath.dotted"
        }
    }

    private var sectionTint: Color {
        switch section.title {
        case "Mapped To / Used By": .orange
        case "Associated Groups": .teal
        case "Scripts": .purple
        case "Packages": .blue
        case "Extension Attributes", "Extension Attributes Used By Associated Groups": .pink
        default: .secondary
        }
    }
}

private struct RelationshipRow: View {
    let item: DependencyItem
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.node.objectType.symbolName)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.node.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Spacer(minLength: 6)

                    if item.node.objectType.supportsEnabledState || item.node.metadata["unresolved"] == "true" {
                        StatusBadge(isEnabled: item.node.isEnabled, isApplicable: item.node.objectType.supportsEnabledState, isUnresolved: item.node.metadata["unresolved"] == "true")
                    }
                }

                HStack(spacing: 6) {
                    RelationshipChip(text: item.relationship, tint: tint)
                    RelationshipChip(text: "ID \(item.node.objectId)", tint: .secondary)
                    if item.node.objectType.supportsScopeCount {
                        RelationshipChip(text: "Scope \(item.node.scopeCount.map(String.init) ?? "Unknown")", tint: .secondary)
                    }
                }

                if let via = item.via, !via.isEmpty {
                    Label("via \(via)", systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(0.55))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct RelationshipChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct IdentityChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

private struct EmptyRelationshipView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No mapped relationships", systemImage: "checkmark.seal")
                .font(.headline)
                .foregroundStyle(.green)
            Text("This object has no detected inbound or outbound dependencies in the current snapshot.")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FindingSection: View {
    let findings: [AnalysisFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Warnings", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.title)
                        .font(.subheadline.bold())
                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

import JamfMapperCore
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AuditSummaryStrip()

                    AuditPanel(
                        title: "Orphaned Objects",
                        subtitle: "Objects with no detected inbound or outbound dependencies.",
                        symbolName: "tray",
                        tint: .teal,
                        groups: groupedByObjectKind(type: .orphan, titlePrefix: "Orphaned"),
                        emptyText: "No orphaned objects found."
                    )

                    AuditPanel(
                        title: "Unused Groups",
                        subtitle: "Smart and static groups with an empty scope.",
                        symbolName: "person.3",
                        tint: .orange,
                        groups: groupedByObjectKind(type: .emptyGroup, titlePrefix: "Empty"),
                        emptyText: "No empty groups found."
                    )

                    AuditPanel(
                        title: "Script Review",
                        subtitle: "Duplicate script content found across Jamf script objects.",
                        symbolName: "terminal",
                        tint: .purple,
                        groups: groupedByFindingType(types: [.duplicateScript]),
                        emptyText: "No duplicate script content found."
                    )

                    AuditPanel(
                        title: "Policy Audit",
                        subtitle: "Policy findings that deserve review before cleanup.",
                        symbolName: "checklist",
                        tint: .blue,
                        groups: groupedByFindingType(types: [.allComputersPolicy, .stalePolicy, .ghostPolicy]),
                        emptyText: "No policy audit findings."
                    )

                    AuditPanel(
                        title: "Group Risk",
                        subtitle: "Circular criteria and high blast-radius group references.",
                        symbolName: "point.3.connected.trianglepath.dotted",
                        tint: .red,
                        groups: groupedByFindingType(types: [.circularSmartGroup, .highBlastRadius]),
                        emptyText: "No circular or high blast-radius group findings."
                    )
                }
                .padding(18)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Audit Reports", systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            Spacer()

            Text("\(state.findings.count) findings")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func groupedByObjectKind(type: FindingType, titlePrefix: String) -> [AuditGroup] {
        let findings = state.findings.filter { $0.type == type }
        let grouped = Dictionary(grouping: findings) { finding in
            objectKind(for: finding) ?? .unknown
        }

        return JamfObjectKind.allCases
            .filter { $0 != .unknown }
            .compactMap { kind in
                guard let findings = grouped[kind], !findings.isEmpty else { return nil }
                return AuditGroup(
                    id: "\(type.rawValue)-\(kind.rawValue)",
                    title: "\(titlePrefix) \(kind.displayName)",
                    subtitle: "\(findings.count) \(findings.count == 1 ? "object" : "objects")",
                    symbolName: kind.symbolName,
                    tint: tint(for: type),
                    findings: sorted(findings)
                )
            }
    }

    private func groupedByFindingType(types: Set<FindingType>) -> [AuditGroup] {
        let findings = state.findings.filter { types.contains($0.type) }
        let grouped = Dictionary(grouping: findings, by: \.type)

        return types
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { type in
                guard let findings = grouped[type], !findings.isEmpty else { return nil }
                return AuditGroup(
                    id: type.rawValue,
                    title: type.displayName,
                    subtitle: "\(findings.count) \(findings.count == 1 ? "finding" : "findings")",
                    symbolName: type.symbolName,
                    tint: tint(for: type),
                    findings: sorted(findings)
                )
            }
    }

    private func objectKind(for finding: AnalysisFinding) -> JamfObjectKind? {
        guard let key = finding.nodeKey else { return nil }
        return state.node(for: key)?.objectType
    }

    private func sorted(_ findings: [AnalysisFinding]) -> [AnalysisFinding] {
        findings.sorted { lhs, rhs in
            let lhsName = lhs.nodeKey.flatMap { state.node(for: $0)?.name } ?? lhs.title
            let rhsName = rhs.nodeKey.flatMap { state.node(for: $0)?.name } ?? rhs.title
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func tint(for type: FindingType) -> Color {
        switch type {
        case .orphan: .teal
        case .emptyGroup, .duplicateScript, .stalePolicy, .ghostPolicy, .allComputersPolicy, .highBlastRadius: .orange
        case .circularSmartGroup: .red
        }
    }
}

private struct AuditSummaryStrip: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            SummaryPill(title: "Orphans", count: count(.orphan), systemImage: "tray", tint: .teal)
            SummaryPill(title: "Empty Groups", count: count(.emptyGroup), systemImage: "person.3", tint: .orange)
            SummaryPill(title: "Scripts", count: count(.duplicateScript), systemImage: "terminal", tint: .purple)
            SummaryPill(title: "Policies", count: policyCount, systemImage: "checklist", tint: .blue)
            SummaryPill(title: "Risk", count: riskCount, systemImage: "exclamationmark.triangle", tint: .red)
        }
    }

    private var policyCount: Int {
        state.findings.filter { [.allComputersPolicy, .stalePolicy, .ghostPolicy].contains($0.type) }.count
    }

    private var riskCount: Int {
        state.findings.filter { [.circularSmartGroup, .highBlastRadius].contains($0.type) }.count
    }

    private func count(_ type: FindingType) -> Int {
        state.findings.filter { $0.type == type }.count
    }
}

private struct SummaryPill: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AuditPanel: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let groups: [AuditGroup]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(groups.reduce(0) { $0 + $1.findings.count })")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            if groups.isEmpty {
                EmptyAuditRow(text: emptyText)
            } else {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        AuditDisclosureGroup(group: group)
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

private struct AuditDisclosureGroup: View {
    let group: AuditGroup

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(group.findings) { finding in
                    AuditFindingRow(finding: finding)
                    if finding.id != group.findings.last?.id {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.symbolName)
                    .foregroundStyle(group.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(group.findings.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(group.tint.opacity(0.14), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AuditFindingRow: View {
    @EnvironmentObject private var state: AppState
    let finding: AnalysisFinding

    private var node: GraphNode? {
        finding.nodeKey.flatMap { state.node(for: $0) }
    }

    var body: some View {
        Button {
            if let node {
                state.selectedNodeKey = node.key
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: node?.objectType.symbolName ?? finding.type.symbolName)
                    .foregroundStyle(rowTint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(node?.name ?? finding.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        if let node, node.objectType.supportsEnabledState || node.metadata["unresolved"] == "true" {
                            StatusBadge(
                                isEnabled: node.isEnabled,
                                isApplicable: node.objectType.supportsEnabledState,
                                isUnresolved: node.metadata["unresolved"] == "true"
                            )
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(node == nil)
    }

    private var subtitle: String {
        guard let node else { return finding.detail }
        var parts = ["ID \(node.objectId)", node.objectType.displayName]
        if node.objectType.supportsScopeCount {
            parts.append("Scope \(node.scopeCount.map(String.init) ?? "Unknown")")
        }
        return parts.joined(separator: " - ")
    }

    private var rowTint: Color {
        switch finding.severity {
        case .info: .teal
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct EmptyAuditRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.green)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AuditGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let findings: [AnalysisFinding]
}

private extension FindingType {
    var displayName: String {
        switch self {
        case .orphan: "Orphaned Objects"
        case .emptyGroup: "Empty Groups"
        case .duplicateScript: "Duplicate Scripts"
        case .stalePolicy: "Stale Disabled Policies"
        case .ghostPolicy: "Empty Policies"
        case .allComputersPolicy: "All Computers Policies"
        case .circularSmartGroup: "Circular Smart Groups"
        case .highBlastRadius: "High Blast-Radius Groups"
        }
    }

    var symbolName: String {
        switch self {
        case .orphan: "tray"
        case .emptyGroup: "person.3"
        case .duplicateScript: "doc.on.doc"
        case .stalePolicy: "clock"
        case .ghostPolicy: "rectangle.dashed"
        case .allComputersPolicy: "globe"
        case .circularSmartGroup: "arrow.2.circlepath"
        case .highBlastRadius: "scope"
        }
    }

    var sortOrder: Int {
        switch self {
        case .orphan: 0
        case .emptyGroup: 1
        case .duplicateScript: 2
        case .allComputersPolicy: 3
        case .stalePolicy: 4
        case .ghostPolicy: 5
        case .circularSmartGroup: 6
        case .highBlastRadius: 7
        }
    }
}

import JamfMapperCore
import SwiftUI

struct GraphScreen: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if state.graph.nodes.isEmpty {
                NoSnapshotPrompt()
            } else if state.visibleNodes.isEmpty {
                EmptyStateView(title: "No Objects", systemImage: "magnifyingglass", detail: "No \(state.selectedObjectKind.displayName.lowercased()) match the current filter.")
            } else {
                List(selection: $state.selectedNodeKey) {
                    Section {
                        ForEach(state.visibleNodes) { node in
                            ObjectRow(
                                node: node,
                                inboundCount: inboundCount(for: node),
                                outboundCount: outboundCount(for: node),
                                showsState: state.selectedObjectKind.supportsEnabledState,
                                showsScope: state.selectedObjectKind.supportsScopeCount
                            )
                                .tag(Optional(node.key))
                        }
                    } header: {
                        ObjectHeader(
                            showsState: state.selectedObjectKind.supportsEnabledState,
                            showsScope: state.selectedObjectKind.supportsScopeCount
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(state.selectedObjectKind.displayName, systemImage: state.selectedObjectKind.symbolName)
                .font(.headline)

            TextField("Search by name or ID", text: $state.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            Toggle("Only orphans", isOn: $state.showOnlyOrphans)
                .toggleStyle(.switch)

            Spacer()

            Text("\(state.visibleNodes.count) shown")
                .foregroundStyle(.secondary)
            Text("\(state.graph.nodes.count) total")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func inboundCount(for node: GraphNode) -> Int {
        state.graph.edges.filter { $0.toKey == node.key }.count
    }

    private func outboundCount(for node: GraphNode) -> Int {
        state.graph.edges.filter { $0.fromKey == node.key }.count
    }
}

private struct NoSnapshotPrompt: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 18) {
            AppBrandIcon()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text("No Jamf objects pulled yet")
                    .font(.title2.bold())
                Text("Run a read-only crawl to build the object list and dependency mappings for this tenant.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            Button {
                Task { await state.recrawlSelectedConnection() }
            } label: {
                Label(state.isCrawling ? "Crawling Jamf Objects" : "Crawl Jamf Objects", systemImage: "tray.and.arrow.down")
                    .frame(minWidth: 190)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.selectedConnection == nil || state.isCrawling)

            if state.isCrawling {
                VStack(spacing: 6) {
                    ProgressView(value: state.progress.fraction)
                        .frame(width: 260)
                    Text(state.progress.currentStage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ObjectHeader: View {
    let showsState: Bool
    let showsScope: Bool

    var body: some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("ID").frame(width: 72, alignment: .leading)
                if showsState {
                    Text("State").frame(width: 86, alignment: .leading)
                }
                if showsScope {
                    Text("Scope").frame(width: 64, alignment: .trailing)
                }
                Text("In").frame(width: 40, alignment: .trailing)
                Text("Out").frame(width: 44, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}

private struct ObjectRow: View {
    let node: GraphNode
    let inboundCount: Int
    let outboundCount: Int
    let showsState: Bool
    let showsScope: Bool

    var body: some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(node.objectType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(node.objectId)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(width: 72, alignment: .leading)

                if showsState {
                    StatusBadge(isEnabled: node.isEnabled, isApplicable: node.objectType.supportsEnabledState, isUnresolved: node.metadata["unresolved"] == "true")
                        .frame(width: 86, alignment: .leading)
                }

                if showsScope {
                    Text(node.scopeCount.map(String.init) ?? "-")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                }

                Text("\(inboundCount)")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text("\(outboundCount)")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Text("\(node.objectType.displayName) ID \(node.objectId)")
            Text(node.key)
        }
    }
}

struct StatusBadge: View {
    let isEnabled: Bool?
    var isApplicable = true
    var isUnresolved = false

    var body: some View {
        let label: String = if isUnresolved {
            "Unresolved"
        } else if !isApplicable {
            "N/A"
        } else if let isEnabled {
            isEnabled ? "Enabled" : "Disabled"
        } else {
            "Unknown"
        }

        let color: Color = if isUnresolved {
            .orange
        } else if !isApplicable {
            .secondary
        } else if isEnabled == true {
            .green
        } else if isEnabled == false {
            .red
        } else {
            .secondary
        }

        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

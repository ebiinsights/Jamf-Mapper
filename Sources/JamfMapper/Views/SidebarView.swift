import JamfMapperCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                CrawlActionCard()
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
                    .listRowBackground(Color.clear)
            }

            Section("Objects") {
                ForEach(state.objectKindsWithCounts, id: \.kind) { item in
                    Button {
                        state.selectObjectKind(item.kind)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.kind.symbolName)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.kind.displayName)
                                    .foregroundStyle(.primary)
                                Text("\(item.count) objects")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if item.orphanCount > 0 {
                                Text("\(item.orphanCount)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(!state.showingAuditReports && item.kind == state.selectedObjectKind ? Color.accentColor.opacity(0.16) : Color.clear)
                }
            }

            Section("Cleanup") {
                Button {
                    state.showAuditReports()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Audit Reports")
                                .foregroundStyle(.primary)
                            Text("\(state.findings.count) findings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(state.showingAuditReports ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct CrawlActionCard: View {
    @EnvironmentObject private var state: AppState

    private var hasSnapshot: Bool {
        !state.graph.nodes.isEmpty
    }

    private var title: String {
        if state.isCrawling { return "Crawling Jamf objects" }
        return hasSnapshot ? "Snapshot ready" : "Ready to pull objects"
    }

    private var detail: String {
        if state.isCrawling { return state.progress.currentStage }
        if hasSnapshot { return "\(state.graph.nodes.count) objects mapped from this tenant." }
        return "Start a read-only crawl to map policies, groups, EAs, scripts, packages, and profiles."
    }

    private var buttonTitle: String {
        hasSnapshot ? "Refresh Objects" : "Crawl Jamf Objects"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: state.isCrawling ? "arrow.triangle.2.circlepath.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state.isCrawling {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: state.progress.fraction)
                    HStack {
                        Text("\(state.progress.completedObjects) of \(max(state.progress.completedObjects, state.progress.totalObjects)) fetched")
                        Spacer()
                        Text(state.progress.errors.isEmpty ? "No errors" : "\(state.progress.errors.count) errors")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await state.recrawlSelectedConnection() }
                } label: {
                    Label(buttonTitle, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(state.selectedConnection == nil)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

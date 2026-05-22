import AppKit
import Combine
import Foundation
import JamfMapperCore
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var connections: [ConnectionProfile] = []
    @Published var selectedConnectionID: UUID?
    @Published var graph = GraphSnapshot()
    @Published var findings: [AnalysisFinding] = []
    @Published var progress = CrawlProgress()
    @Published var selectedObjectKind: JamfObjectKind = .policy
    @Published var selectedNodeKey: String?
    @Published var searchText = ""
    @Published var selectedTypes: Set<JamfObjectKind> = Set(JamfObjectKind.allCases)
    @Published var showOnlyOrphans = false
    @Published var isCrawling = false
    @Published var showingAuditReports = false
    @Published var errorMessage: String?

    private(set) var store: DatabaseStore?
    private let keychain = KeychainClient()
    private let analyzer = GraphAnalyzer()
    private let dependencyResolver = DependencyResolver()

    init() {
        do {
            let databaseURL = try DatabaseStore.defaultDatabaseURL()
            store = try DatabaseStore(databaseURL: databaseURL)
            connections = try store?.connections() ?? []
            selectedConnectionID = UserDefaults.standard.string(forKey: "selectedConnectionID").flatMap(UUID.init(uuidString:)) ?? connections.first?.id
            if let selectedConnectionID, let snapshotID = try store?.latestSnapshotID(for: selectedConnectionID), let loadedGraph = try store?.graph(snapshotID: snapshotID) {
                graph = loadedGraph
                findings = analyzer.analyze(graph: loadedGraph)
                selectInitialObject()
            }
        } catch {
            store = nil
            errorMessage = error.localizedDescription
        }
    }

    var selectedConnection: ConnectionProfile? {
        connections.first { $0.id == selectedConnectionID }
    }

    var filteredGraph: GraphSnapshot {
        let orphanKeys = showOnlyOrphans ? Set(findings.filter { $0.type == .orphan }.compactMap(\.nodeKey)) : nil
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes = graph.nodes.filter { node in
            selectedTypes.contains(node.objectType)
            && (orphanKeys == nil || orphanKeys?.contains(node.key) == true)
            && (trimmedSearch.isEmpty || node.name.localizedCaseInsensitiveContains(trimmedSearch) || node.objectId.localizedCaseInsensitiveContains(trimmedSearch))
        }
        let nodeKeys = Set(nodes.map(\.key))
        let edges = graph.edges.filter { nodeKeys.contains($0.fromKey) && nodeKeys.contains($0.toKey) }
        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    var selectedNode: GraphNode? {
        guard let selectedNodeKey else { return nil }
        return graph.nodes.first { $0.key == selectedNodeKey }
    }

    var objectKindsWithCounts: [(kind: JamfObjectKind, count: Int, orphanCount: Int)] {
        let orphanKeys = Set(findings.filter { $0.type == .orphan }.compactMap(\.nodeKey))
        return JamfObjectKind.allCases
            .filter { $0 != .unknown }
            .map { kind in
                let nodes = graph.nodes.filter { $0.objectType == kind }
                let orphanCount = nodes.filter { orphanKeys.contains($0.key) }.count
                return (kind, nodes.count, orphanCount)
            }
            .filter { $0.count > 0 || $0.kind == selectedObjectKind }
    }

    var visibleNodes: [GraphNode] {
        let orphanKeys = showOnlyOrphans ? Set(findings.filter { $0.type == .orphan }.compactMap(\.nodeKey)) : nil
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return graph.nodes
            .filter { $0.objectType == selectedObjectKind }
            .filter { orphanKeys == nil || orphanKeys?.contains($0.key) == true }
            .filter { trimmedSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmedSearch) || $0.objectId.localizedCaseInsensitiveContains(trimmedSearch) }
            .sorted {
                if ($0.isEnabled ?? true) != ($1.isEnabled ?? true) {
                    return ($0.isEnabled ?? true) && !($1.isEnabled ?? true)
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var selectedDependencySections: [DependencySection] {
        guard let selectedNodeKey else { return [] }
        return dependencyResolver.sections(for: selectedNodeKey, in: graph)
    }

    func selectConnection(_ connection: ConnectionProfile?) {
        selectedConnectionID = connection?.id
        if let id = connection?.id {
            UserDefaults.standard.set(id.uuidString, forKey: "selectedConnectionID")
            loadLatestSnapshot(connectionID: id)
        }
    }

    func selectObjectKind(_ kind: JamfObjectKind) {
        showingAuditReports = false
        selectedObjectKind = kind
        selectedNodeKey = visibleNodes.first?.key
    }

    func showAuditReports() {
        showingAuditReports = true
    }

    func node(for key: String) -> GraphNode? {
        graph.nodes.first { $0.key == key }
    }

    func saveConnection(name: String, urlString: String, clientID: String, clientSecret: String) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased()) else {
            errorMessage = "Enter a valid Jamf URL, including https://."
            return
        }
        guard let store else {
            errorMessage = "The database is not available."
            return
        }
        let connection = ConnectionProfile(name: name.isEmpty ? url.host ?? "Jamf Tenant" : name, baseURL: url, clientID: clientID)
        do {
            try keychain.saveClientSecret(clientSecret, connectionID: connection.id)
            let client = JamfAPIClient(baseURL: url, clientID: clientID, clientSecret: clientSecret)
            _ = try await client.validateConnection()
            try store.upsertConnection(connection)
            connections = try store.connections()
            selectConnection(connection)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOutSelectedConnection() {
        guard let connection = selectedConnection, let store else { return }
        do {
            try keychain.deleteClientSecret(connectionID: connection.id)
            try store.deleteConnection(id: connection.id)
            connections = try store.connections()
            graph = GraphSnapshot()
            findings = []
            selectedNodeKey = nil
            progress = CrawlProgress()

            if let nextConnection = connections.first {
                selectConnection(nextConnection)
            } else {
                selectedConnectionID = nil
                UserDefaults.standard.removeObject(forKey: "selectedConnectionID")
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recrawlSelectedConnection() async {
        guard let connection = selectedConnection, let store else { return }
        isCrawling = true
        progress = CrawlProgress(currentStage: "Connecting")
        errorMessage = nil
        do {
            let secret = try keychain.clientSecret(connectionID: connection.id)
            let client = JamfAPIClient(baseURL: connection.baseURL, clientID: connection.clientID, clientSecret: secret)
            let crawler = JamfCrawler(apiClient: client, store: store)
            let snapshotID = try await crawler.crawl(connectionID: connection.id) { [weak self] progress in
                await MainActor.run { self?.progress = progress }
            }
            graph = try store.graph(snapshotID: snapshotID)
            findings = analyzer.analyze(graph: graph)
            selectInitialObject()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCrawling = false
    }

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "jamfmapper-graph.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try GraphExporter().exportJSON(graph: filteredGraph, to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func exportCSV() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try GraphExporter().exportCSV(graph: filteredGraph, directory: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openSelectedNodeInJamf() {
        guard let selectedConnection, let node = selectedNode else { return }
        guard let url = JamfConsoleURLBuilder.url(for: node, baseURL: selectedConnection.baseURL) else {
            errorMessage = "Jamf Mapper does not have a console link for this object type yet."
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func loadLatestSnapshot(connectionID: UUID) {
        do {
            if let snapshotID = try store?.latestSnapshotID(for: connectionID), let loadedGraph = try store?.graph(snapshotID: snapshotID) {
                graph = loadedGraph
                findings = analyzer.analyze(graph: loadedGraph)
                selectInitialObject()
            } else {
                graph = GraphSnapshot()
                findings = []
                selectedNodeKey = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectInitialObject() {
        if graph.nodes.contains(where: { $0.objectType == selectedObjectKind }) {
            selectedNodeKey = visibleNodes.first?.key
            return
        }
        selectedObjectKind = objectKindsWithCounts.first(where: { $0.count > 0 })?.kind ?? .policy
        selectedNodeKey = visibleNodes.first?.key
    }
}

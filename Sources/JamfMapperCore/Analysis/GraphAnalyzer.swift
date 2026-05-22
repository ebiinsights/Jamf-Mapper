import Foundation

public enum FindingSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public enum FindingType: String, Codable, Sendable {
    case orphan
    case emptyGroup
    case duplicateScript
    case stalePolicy
    case ghostPolicy
    case allComputersPolicy
    case circularSmartGroup
    case highBlastRadius
}

public struct AnalysisFinding: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: FindingType
    public var severity: FindingSeverity
    public var nodeKey: String?
    public var title: String
    public var detail: String
    public var metadata: [String: String]

    public init(id: UUID = UUID(), type: FindingType, severity: FindingSeverity, nodeKey: String? = nil, title: String, detail: String, metadata: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.severity = severity
        self.nodeKey = nodeKey
        self.title = title
        self.detail = detail
        self.metadata = metadata
    }
}

public struct GraphAnalyzer: Sendable {
    public init() {}

    public func analyze(graph: GraphSnapshot, stalePolicyCutoff: Date = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()) -> [AnalysisFinding] {
        var findings: [AnalysisFinding] = []
        let incoming = Dictionary(grouping: graph.edges, by: \.toKey)
        let outgoing = Dictionary(grouping: graph.edges, by: \.fromKey)

        for node in graph.nodes {
            if incoming[node.key, default: []].isEmpty && outgoing[node.key, default: []].isEmpty {
                findings.append(.init(type: .orphan, severity: .info, nodeKey: node.key, title: "Orphaned \(node.objectType.displayName)", detail: "\(node.name) has no incoming or outgoing dependencies."))
            }

            if [.smartGroup, .staticGroup].contains(node.objectType), node.scopeCount == 0 {
                findings.append(.init(type: .emptyGroup, severity: .warning, nodeKey: node.key, title: "Empty group", detail: "\(node.name) currently has no scoped computers."))
            }

            if node.objectType == .policy, node.isEnabled == false, let modified = node.lastModified, modified < stalePolicyCutoff {
                findings.append(.init(type: .stalePolicy, severity: .warning, nodeKey: node.key, title: "Stale disabled policy", detail: "\(node.name) has been disabled for more than 90 days."))
            }

            if node.objectType == .policy, outgoing[node.key, default: []].isEmpty {
                findings.append(.init(type: .ghostPolicy, severity: .warning, nodeKey: node.key, title: "Empty policy", detail: "\(node.name) has no detected packages, scripts, scope, or management actions."))
            }
        }

        findings += duplicateScripts(graph: graph)
        findings += circularSmartGroups(graph: graph)
        findings += blastRadiusFindings(graph: graph)
        return findings.sorted { $0.title < $1.title }
    }

    public func safeDeleteOrder(selectedKeys: Set<String>, graph: GraphSnapshot) -> [String] {
        let selectedEdges = graph.edges.filter { selectedKeys.contains($0.fromKey) && selectedKeys.contains($0.toKey) }
        var dependencies = Dictionary(grouping: selectedEdges, by: \.fromKey).mapValues { Set($0.map(\.toKey)) }
        var result: [String] = []
        var remaining = selectedKeys

        while !remaining.isEmpty {
            let ready = remaining.filter { dependencies[$0, default: []].isDisjoint(with: remaining) || dependencies[$0, default: []].isEmpty }
            if ready.isEmpty {
                result.append(contentsOf: remaining.sorted())
                break
            }
            for key in ready.sorted() {
                result.append(key)
                remaining.remove(key)
                dependencies.removeValue(forKey: key)
            }
        }
        return result
    }

    private func duplicateScripts(graph: GraphSnapshot) -> [AnalysisFinding] {
        let scripts = graph.nodes.filter { $0.objectType == .script && ($0.rawHash?.isEmpty == false) }
        let grouped = Dictionary(grouping: scripts, by: { $0.rawHash ?? "" })
        return grouped.values
            .filter { $0.count > 1 }
            .map { group in
                let names = group.map(\.name).sorted()
                return AnalysisFinding(
                    type: .duplicateScript,
                    severity: .warning,
                    nodeKey: group.first?.key,
                    title: "Duplicate script content",
                    detail: names.joined(separator: ", "),
                    metadata: ["count": String(group.count)]
                )
            }
    }

    private func circularSmartGroups(graph: GraphSnapshot) -> [AnalysisFinding] {
        let smartKeys = Set(graph.nodes.filter { $0.objectType == .smartGroup }.map(\.key))
        let edges = graph.edges.filter { $0.kind == .nestedSmartGroup && smartKeys.contains($0.fromKey) && smartKeys.contains($0.toKey) }
        let components = Tarjan.stronglyConnectedComponents(nodes: Array(smartKeys), edges: edges.map { ($0.fromKey, $0.toKey) })
        return components.filter { $0.count > 1 }.map { component in
            AnalysisFinding(
                type: .circularSmartGroup,
                severity: .critical,
                title: "Circular smart group criteria",
                detail: component.sorted().joined(separator: " -> "),
                metadata: ["count": String(component.count)]
            )
        }
    }

    private func blastRadiusFindings(graph: GraphSnapshot) -> [AnalysisFinding] {
        let incoming = Dictionary(grouping: graph.edges.filter { $0.kind == .scopedToGroup || $0.kind == .excludesGroup }, by: \.toKey)
        return graph.nodes
            .filter { [.smartGroup, .staticGroup].contains($0.objectType) }
            .compactMap { node in
                let count = incoming[node.key, default: []].count
                guard count >= 10 else { return nil }
                return AnalysisFinding(
                    type: .highBlastRadius,
                    severity: .warning,
                    nodeKey: node.key,
                    title: "High blast-radius group",
                    detail: "\(node.name) is referenced by \(count) policies, profiles, or apps.",
                    metadata: ["referenceCount": String(count)]
                )
            }
    }
}

enum Tarjan {
    static func stronglyConnectedComponents(nodes: [String], edges: [(String, String)]) -> [[String]] {
        var index = 0
        var stack: [String] = []
        var onStack: Set<String> = []
        var indices: [String: Int] = [:]
        var lowlinks: [String: Int] = [:]
        var result: [[String]] = []
        let adjacency = Dictionary(grouping: edges, by: { $0.0 }).mapValues { $0.map(\.1) }

        func strongConnect(_ node: String) {
            indices[node] = index
            lowlinks[node] = index
            index += 1
            stack.append(node)
            onStack.insert(node)

            for neighbor in adjacency[node, default: []] {
                if indices[neighbor] == nil {
                    strongConnect(neighbor)
                    lowlinks[node] = min(lowlinks[node] ?? 0, lowlinks[neighbor] ?? 0)
                } else if onStack.contains(neighbor) {
                    lowlinks[node] = min(lowlinks[node] ?? 0, indices[neighbor] ?? 0)
                }
            }

            if lowlinks[node] == indices[node] {
                var component: [String] = []
                while let last = stack.popLast() {
                    onStack.remove(last)
                    component.append(last)
                    if last == node { break }
                }
                result.append(component)
            }
        }

        for node in nodes where indices[node] == nil {
            strongConnect(node)
        }
        return result
    }
}

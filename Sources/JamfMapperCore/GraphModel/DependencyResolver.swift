import Foundation

public struct DependencySection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var items: [DependencyItem]

    public init(title: String, items: [DependencyItem]) {
        self.id = title
        self.title = title
        self.items = items
    }
}

public struct DependencyItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var node: GraphNode
    public var relationship: String
    public var via: String?
    public var evidence: [String: String]

    public init(node: GraphNode, relationship: String, via: String? = nil, evidence: [String: String] = [:]) {
        self.id = "\(relationship):\(node.key):\(via ?? "")"
        self.node = node
        self.relationship = relationship
        self.via = via
        self.evidence = evidence
    }
}

public struct DependencyResolver: Sendable {
    public init() {}

    public func sections(for nodeKey: String, in graph: GraphSnapshot) -> [DependencySection] {
        guard let node = graph.nodes.first(where: { $0.key == nodeKey }) else { return [] }

        let nodesByKey = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.key, $0) })
        let outgoing = graph.edges.filter { $0.fromKey == nodeKey }
        let incoming = graph.edges.filter { $0.toKey == nodeKey }

        var sections: [DependencySection] = []
        sections += directDependencySections(for: node, outgoing: outgoing, nodesByKey: nodesByKey)
        sections += incomingSections(for: node, incoming: incoming, nodesByKey: nodesByKey)

        if node.objectType == .policy {
            let eaItems = outgoing
                .filter { $0.kind == .evaluatesEA && $0.evidence["viaGroupName"] != nil }
                .compactMap { edge -> DependencyItem? in
                    guard let target = nodesByKey[edge.toKey] else { return nil }
                    return DependencyItem(node: target, relationship: "EA used by scoped group criteria", via: edge.evidence["viaGroupName"], evidence: edge.evidence)
                }
                .deduplicated()
            if !eaItems.isEmpty {
                sections.insert(DependencySection(title: "Extension Attributes Used By Associated Groups", items: eaItems), at: min(2, sections.count))
            }
        }

        return sections.filter { !$0.items.isEmpty }
    }

    private func directDependencySections(for node: GraphNode, outgoing: [GraphEdge], nodesByKey: [String: GraphNode]) -> [DependencySection] {
        let buckets: [(String, Set<GraphEdgeKind>)] = [
            ("Associated Groups", [.scopedToGroup, .excludesGroup]),
            ("Scripts", [.usesScript]),
            ("Packages", [.installsPackage]),
            ("Extension Attributes", [.evaluatesEA]),
            ("Categories", [.inCategory]),
            ("Printers", [.usesPrinter]),
            ("Dock Items", [.usesDockItem]),
            ("Directory Bindings", [.usesDirectoryBinding]),
            ("Network Segments", [.referencesNetworkSegment]),
            ("Patch Dependencies", [.dependsOnPatchTitle, .dependsOnPatchConfiguration]),
            ("Nested Groups and Searches", [.nestedSmartGroup, .basedOnAdvancedSearch]),
            ("Other Dependencies", [.referencesObject, .deploysMacApp, .hasDeclaration])
        ]

        return buckets.compactMap { title, kinds in
            let items = outgoing
                .filter { kinds.contains($0.kind) }
                .filter { !(node.objectType == .policy && $0.kind == .evaluatesEA && $0.evidence["viaGroupName"] != nil) }
                .compactMap { edge -> DependencyItem? in
                    guard let target = nodesByKey[edge.toKey] else { return nil }
                    let relationship = outgoingRelationship(edge.kind)
                    return DependencyItem(node: target, relationship: relationship, via: edge.evidence["viaGroupName"], evidence: edge.evidence)
                }
                .deduplicated()
            return items.isEmpty ? nil : DependencySection(title: title, items: items)
        }
    }

    private func incomingSections(for node: GraphNode, incoming: [GraphEdge], nodesByKey: [String: GraphNode]) -> [DependencySection] {
        let usedBy = incoming.compactMap { edge -> DependencyItem? in
            guard let source = nodesByKey[edge.fromKey] else { return nil }
            return DependencyItem(node: source, relationship: incomingRelationship(edge.kind, selectedNode: node), via: edge.evidence["viaGroupName"], evidence: edge.evidence)
        }
        return usedBy.isEmpty ? [] : [DependencySection(title: "Mapped To / Used By", items: usedBy.deduplicated())]
    }

    private func incomingRelationship(_ kind: GraphEdgeKind, selectedNode: GraphNode) -> String {
        switch kind {
        case .usesScript: "Executes this script"
        case .installsPackage: "Installs this package"
        case .scopedToGroup: "Scoped to this group"
        case .excludesGroup: "Excludes this group"
        case .evaluatesEA:
            selectedNode.objectType == .extensionAttribute ? "Evaluates this EA" : "References this object"
        case .inCategory: "Assigned to this category"
        case .usesPrinter: "Maps this printer"
        case .usesDockItem: "Uses this dock item"
        case .usesDirectoryBinding: "Uses this directory binding"
        case .referencesNetworkSegment: "References this network segment"
        case .dependsOnPatchTitle: "Depends on this patch title"
        case .dependsOnPatchConfiguration: "Depends on this patch configuration"
        case .nestedSmartGroup: "Criteria references this group"
        case .basedOnAdvancedSearch: "Based on this advanced search"
        case .deploysMacApp: "Deploys this Mac app"
        case .hasDeclaration: "Contains this declaration"
        case .referencesObject: "References this object"
        }
    }

    private func outgoingRelationship(_ kind: GraphEdgeKind) -> String {
        switch kind {
        case .usesScript: "Executes"
        case .installsPackage: "Installs"
        case .scopedToGroup: "Scoped"
        case .excludesGroup: "Excluded"
        case .evaluatesEA: "Evaluates"
        case .nestedSmartGroup: "References group in criteria"
        case .basedOnAdvancedSearch: "Based on search"
        case .inCategory: "Assigned category"
        case .referencesNetworkSegment: "Scoped to network segment"
        case .usesPrinter: "Maps printer"
        case .usesDockItem: "Adds dock item"
        case .usesDirectoryBinding: "Uses directory binding"
        case .deploysMacApp: "Deploys"
        case .dependsOnPatchTitle: "Patch title"
        case .dependsOnPatchConfiguration: "Patch configuration"
        case .hasDeclaration: "Contains declaration"
        case .referencesObject: "References"
        }
    }
}

private extension Array where Element == DependencyItem {
    func deduplicated() -> [DependencyItem] {
        var seen: Set<String> = []
        var result: [DependencyItem] = []
        for item in self {
            let key = "\(item.node.key):\(item.relationship):\(item.via ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result.sorted {
            if $0.node.objectType == $1.node.objectType {
                return $0.node.name.localizedCaseInsensitiveCompare($1.node.name) == .orderedAscending
            }
            return $0.node.objectType.displayName < $1.node.objectType.displayName
        }
    }
}

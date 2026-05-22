import Foundation

public struct GraphExtractor: Sendable {
    public init() {}

    public func extract(rawObjects: [RawJamfObject]) -> GraphSnapshot {
        var nodesByKey: [String: GraphNode] = [:]

        for object in rawObjects {
            let node = buildNode(from: object)
            nodesByKey[node.key] = merge(existing: nodesByKey[node.key], incoming: node)
            if let embeddedScriptNode = buildEmbeddedScriptNode(from: object) {
                nodesByKey[embeddedScriptNode.key] = merge(existing: nodesByKey[embeddedScriptNode.key], incoming: embeddedScriptNode)
            }
        }

        let context = ExtractionContext(nodes: Array(nodesByKey.values))
        var edgesByKey: [String: GraphEdge] = [:]

        for object in rawObjects {
            let sourceNode = buildNode(from: object)
            for edge in extractEdges(rawObject: object, sourceNode: sourceNode, context: context) {
                edgesByKey[edge.key] = edge
                if nodesByKey[edge.toKey] == nil {
                    let unresolved = unresolvedNode(for: edge.toKey, fallbackName: edge.evidence["targetName"] ?? edge.toKey)
                    nodesByKey[unresolved.key] = unresolved
                }
            }
        }

        addPolicyEAEdges(nodesByKey: nodesByKey, edgesByKey: &edgesByKey)

        return GraphSnapshot(
            nodes: Array(nodesByKey.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            edges: Array(edgesByKey.values).sorted { $0.key < $1.key }
        )
    }

    private func buildNode(from raw: RawJamfObject) -> GraphNode {
        let parsed = raw.payload.decodedDictionary()
        let root = parsed.map { likelyRoot(for: raw.objectType, dictionary: $0) } ?? [:]
        let kind = groupKindIfNeeded(raw.objectType, root: root)
        let objectID = JSONValueReader.string(root, keys: ["id", "general.id", "definitionId", "groupJamfProId", "packageId"]) ?? raw.objectID
        let name = JSONValueReader.string(root, keys: ["general.name", "name", "displayName", "groupName", "packageName", "fileName"]) ?? raw.name
        let category = JSONValueReader.string(root, keys: ["general.category.name", "category.name", "category"])
        let enabled = JSONValueReader.bool(root, keys: ["general.enabled", "enabled", "isEnabled"])
        let scopeCount = JSONValueReader.int(root, keys: ["scope.size", "scope_count", "membershipCount", "computers.size", "site.membershipCount"])

        let scriptHash: String?
        let scriptSource = scriptSource(in: root)
        if kind == .script || kind == .extensionAttribute {
            scriptHash = scriptSource.map { Data($0.utf8).sha256Hex }
        } else {
            scriptHash = raw.contentHash
        }

        var metadata = ["endpoint": raw.endpoint]
        if let scriptSource, !scriptSource.isEmpty {
            metadata["scriptSource"] = scriptSource
        }

        return GraphNode(
            key: GraphNode.key(for: kind, id: objectID),
            objectType: kind,
            objectId: objectID,
            name: name,
            category: category,
            isEnabled: enabled,
            scopeCount: scopeCount,
            lastModified: nil,
            rawHash: scriptHash,
            source: raw.source,
            metadata: metadata
        )
    }

    private func buildEmbeddedScriptNode(from raw: RawJamfObject) -> GraphNode? {
        guard raw.objectType == .extensionAttribute,
              let dictionary = raw.payload.decodedDictionary()
        else { return nil }

        let root = likelyRoot(for: raw.objectType, dictionary: dictionary)
        guard JSONValueReader.string(root, keys: ["input_type.type", "inputType"])?.localizedCaseInsensitiveContains("script") == true,
              let script = scriptSource(in: root),
              !script.isEmpty
        else { return nil }

        let objectID = JSONValueReader.string(root, keys: ["id", "general.id"]) ?? raw.objectID
        let name = JSONValueReader.string(root, keys: ["general.name", "name", "displayName"]) ?? raw.name
        let sourceEAKey = GraphNode.key(for: .extensionAttribute, id: objectID)

        return GraphNode(
            key: GraphNode.key(for: .script, id: "embedded-ea-\(objectID)"),
            objectType: .script,
            objectId: "embedded-ea-\(objectID)",
            name: "\(name) embedded script",
            rawHash: Data(script.utf8).sha256Hex,
            source: .derived,
            metadata: [
                "endpoint": raw.endpoint,
                "scriptSource": script,
                "sourceEAKey": sourceEAKey,
                "sourceEAId": objectID,
                "sourceEAName": name
            ]
        )
    }

    private func extractEdges(rawObject: RawJamfObject, sourceNode: GraphNode, context: ExtractionContext) -> [GraphEdge] {
        guard let dictionary = rawObject.payload.decodedDictionary() else { return [] }
        let root = likelyRoot(for: rawObject.objectType, dictionary: dictionary)
        var edges: [GraphEdge] = []

        if let categoryName = JSONValueReader.string(root, keys: ["general.category.name", "category.name", "category"]) {
            edges.append(edge(from: sourceNode, to: .category, id: JSONValueReader.string(root, keys: ["general.category.id", "category.id"]), name: categoryName, kind: .inCategory, evidencePath: "category", context: context))
        }

        switch sourceNode.objectType {
        case .policy:
            edges += references(root, keys: ["scripts.script", "scripts", "script"], target: .script, edgeKind: .usesScript, source: sourceNode, path: "scripts", context: context)
            edges += references(root, keys: ["package_configuration.packages.package", "packages.package", "packages"], target: .package, edgeKind: .installsPackage, source: sourceNode, path: "packages", context: context)
            edges += references(root, keys: ["printers.printer", "printers"], target: .printer, edgeKind: .usesPrinter, source: sourceNode, path: "printers", context: context)
            edges += references(root, keys: ["dock_items.dock_item", "dock_items", "dockItems"], target: .dockItem, edgeKind: .usesDockItem, source: sourceNode, path: "dock_items", context: context)
            edges += references(root, keys: ["directory_bindings.directory_binding", "directory_bindings", "directoryBindings"], target: .directoryBinding, edgeKind: .usesDirectoryBinding, source: sourceNode, path: "directory_bindings", context: context)
            edges += groupReferences(root, keys: ["scope.computer_groups.computer_group", "scope.computer_groups", "scope.computerGroups"], edgeKind: .scopedToGroup, source: sourceNode, path: "scope.computer_groups", context: context)
            edges += groupReferences(root, keys: ["scope.exclusions.computer_groups.computer_group", "scope.exclusions.computerGroups"], edgeKind: .excludesGroup, source: sourceNode, path: "scope.exclusions", context: context)
            edges += references(root, keys: ["scope.network_segments.network_segment", "scope.networkSegments"], target: .networkSegment, edgeKind: .referencesNetworkSegment, source: sourceNode, path: "scope.network_segments", context: context)
        case .smartGroup, .advancedSearch:
            edges += criteriaEdges(root, source: sourceNode, context: context)
        case .computerConfigurationProfile, .mobileConfigurationProfile, .restrictedSoftware, .macApplication, .appInstaller:
            edges += groupReferences(root, keys: ["scope.computer_groups.computer_group", "scope.computer_groups", "scope.computerGroups", "scope.mobile_device_groups.mobile_device_group"], edgeKind: .scopedToGroup, source: sourceNode, path: "scope", context: context)
            edges += groupReferences(root, keys: ["scope.exclusions.computer_groups.computer_group", "scope.exclusions.mobile_device_groups.mobile_device_group"], edgeKind: .excludesGroup, source: sourceNode, path: "scope.exclusions", context: context)
        case .patchPolicy:
            if let titleID = JSONValueReader.string(root, keys: ["softwareTitleId"]) {
                edges.append(GraphEdge(fromKey: sourceNode.key, toKey: GraphNode.key(for: .patchTitle, id: titleID), kind: .dependsOnPatchTitle, evidence: ["path": "softwareTitleId"]))
            }
            if let configID = JSONValueReader.string(root, keys: ["softwareTitleConfigurationId"]) {
                edges.append(GraphEdge(fromKey: sourceNode.key, toKey: GraphNode.key(for: .patchSoftwareTitleConfiguration, id: configID), kind: .dependsOnPatchConfiguration, evidence: ["path": "softwareTitleConfigurationId"]))
            }
        case .computerPrestage:
            edges += groupReferences(root, keys: ["scope.assignments", "scope.computer_groups"], edgeKind: .scopedToGroup, source: sourceNode, path: "scope", context: context)
        default:
            break
        }

        if sourceNode.objectType == .extensionAttribute,
           JSONValueReader.string(root, keys: ["input_type.type", "inputType"])?.localizedCaseInsensitiveContains("script") == true,
           scriptSource(in: root) != nil {
            let scriptKey = GraphNode.key(for: .script, id: "embedded-ea-\(sourceNode.objectId)")
            edges.append(GraphEdge(fromKey: sourceNode.key, toKey: scriptKey, kind: .usesScript, label: "SCRIPT_INPUT", evidence: ["path": "script_contents", "targetName": "\(sourceNode.name) embedded script"]))
        }

        return edges
    }

    private func references(_ root: [String: Any], keys: [String], target: JamfObjectKind, edgeKind: GraphEdgeKind, source: GraphNode, path: String, context: ExtractionContext) -> [GraphEdge] {
        referenceDictionaries(root, keys: keys).compactMap { ref in
            guard let name = JSONValueReader.string(ref, keys: ["name", "displayName", "groupName"]) else { return nil }
            return edge(from: source, to: target, id: JSONValueReader.string(ref, keys: ["id", "groupJamfProId"]), name: name, kind: edgeKind, evidencePath: path, context: context)
        }
    }

    private func groupReferences(_ root: [String: Any], keys: [String], edgeKind: GraphEdgeKind, source: GraphNode, path: String, context: ExtractionContext) -> [GraphEdge] {
        referenceDictionaries(root, keys: keys).compactMap { ref in
            guard let name = JSONValueReader.string(ref, keys: ["name", "displayName", "groupName"]) else { return nil }
            let id = JSONValueReader.string(ref, keys: ["id", "groupJamfProId"])
            let key = context.groupKey(id: id, name: name) ?? id.map { GraphNode.key(for: .smartGroup, id: $0) } ?? GraphNode.unresolvedKey(for: .smartGroup, name: name)
            return GraphEdge(fromKey: source.key, toKey: key, kind: edgeKind, evidence: ["path": path, "targetName": name])
        }
    }

    private func referenceDictionaries(_ root: [String: Any], keys: [String]) -> [[String: Any]] {
        var refs: [[String: Any]] = []
        for key in keys {
            guard let value = JSONValueReader.value(root, path: key.split(separator: ".").map(String.init)) else { continue }
            if let array = value as? [[String: Any]] {
                refs += array
            } else if let dict = value as? [String: Any] {
                refs.append(dict)
            }
        }
        return refs
    }

    private func criteriaEdges(_ root: [String: Any], source: GraphNode, context: ExtractionContext) -> [GraphEdge] {
        let criteria = JSONValueReader.array(root, keys: ["criteria.criterion", "criteria", "groupCriteria"])
        var edges: [GraphEdge] = []
        for criterion in criteria {
            let name = JSONValueReader.string(criterion, keys: ["name", "field"]) ?? ""
            let value = JSONValueReader.string(criterion, keys: ["value", "searchValue"]) ?? ""

            if let eaKey = context.extensionAttributeKey(name: name) ?? context.extensionAttributeKey(name: value) {
                edges.append(GraphEdge(fromKey: source.key, toKey: eaKey, kind: .evaluatesEA, evidence: ["path": "criteria", "targetName": context.nodeName(for: eaKey) ?? name]))
            } else if name.localizedCaseInsensitiveContains("extension attribute") || name.localizedCaseInsensitiveContains("ea") {
                let targetName = value.isEmpty ? name : value
                edges.append(edge(from: source, to: .extensionAttribute, id: nil, name: targetName, kind: .evaluatesEA, evidencePath: "criteria", context: context))
            }

            if name.localizedCaseInsensitiveContains("computer group") || name.localizedCaseInsensitiveContains("member of") {
                let targetName = value.isEmpty ? name : value
                let key = context.groupKey(id: nil, name: targetName) ?? GraphNode.unresolvedKey(for: .smartGroup, name: targetName)
                edges.append(GraphEdge(fromKey: source.key, toKey: key, kind: .nestedSmartGroup, evidence: ["path": "criteria", "targetName": targetName]))
            }

            if name.localizedCaseInsensitiveContains("advanced") {
                edges.append(edge(from: source, to: .advancedSearch, id: nil, name: value, kind: .basedOnAdvancedSearch, evidencePath: "criteria", context: context))
            }
        }
        return edges
    }

    private func edge(from source: GraphNode, to target: JamfObjectKind, id: String?, name: String, kind: GraphEdgeKind, evidencePath: String, context: ExtractionContext) -> GraphEdge {
        let targetKey = context.key(type: target, id: id, name: name) ?? id.map { GraphNode.key(for: target, id: $0) } ?? GraphNode.unresolvedKey(for: target, name: name)
        return GraphEdge(fromKey: source.key, toKey: targetKey, kind: kind, evidence: ["path": evidencePath, "targetName": name])
    }

    private func addPolicyEAEdges(nodesByKey: [String: GraphNode], edgesByKey: inout [String: GraphEdge]) {
        let scopedGroupsByPolicy = Dictionary(
            grouping: edgesByKey.values.filter { $0.kind == .scopedToGroup || $0.kind == .excludesGroup },
            by: \.fromKey
        )
        let groupCriteriaEdges = Dictionary(
            grouping: edgesByKey.values.filter { $0.kind == .evaluatesEA || $0.kind == .nestedSmartGroup },
            by: \.fromKey
        )

        for policy in nodesByKey.values where policy.objectType == .policy {
            let initialGroups = scopedGroupsByPolicy[policy.key, default: []].map(\.toKey)
            var visitedGroups: Set<String> = []
            var queue = initialGroups

            while let groupKey = queue.first {
                queue.removeFirst()
                guard visitedGroups.insert(groupKey).inserted else { continue }
                for groupEdge in groupCriteriaEdges[groupKey, default: []] {
                    if groupEdge.kind == .nestedSmartGroup {
                        queue.append(groupEdge.toKey)
                    } else if groupEdge.kind == .evaluatesEA {
                        let viaName = nodesByKey[groupKey]?.name ?? groupEdge.fromKey
                        let eaName = nodesByKey[groupEdge.toKey]?.name ?? groupEdge.evidence["targetName"] ?? groupEdge.toKey
                        let edge = GraphEdge(
                            fromKey: policy.key,
                            toKey: groupEdge.toKey,
                            kind: .evaluatesEA,
                            label: "EVALUATES_EA_VIA_GROUP",
                            evidence: ["path": "scope.group.criteria", "viaGroupKey": groupKey, "viaGroupName": viaName, "targetName": eaName]
                        )
                        edgesByKey[edge.key] = edge
                    }
                }
            }
        }
    }

    private func unresolvedNode(for key: String, fallbackName: String) -> GraphNode {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let type = JamfObjectKind(rawValue: parts.first ?? "") ?? .unknown
        let objectID = parts.count > 1 ? parts[1] : key
        return GraphNode(key: key, objectType: type, objectId: objectID, name: fallbackName, source: .derived, metadata: ["unresolved": "true"])
    }

    private func likelyRoot(for type: JamfObjectKind, dictionary: [String: Any]) -> [String: Any] {
        let keys: [String]
        switch type {
        case .policy: keys = ["policy"]
        case .smartGroup, .staticGroup: keys = ["computer_group", "group"]
        case .extensionAttribute: keys = ["computer_extension_attribute"]
        case .script: keys = ["script"]
        case .category: keys = ["category"]
        case .advancedSearch: keys = ["advanced_computer_search"]
        case .package: keys = ["package"]
        case .printer: keys = ["printer"]
        case .dockItem: keys = ["dock_item"]
        case .directoryBinding: keys = ["directory_binding"]
        case .networkSegment: keys = ["network_segment"]
        case .computerConfigurationProfile: keys = ["os_x_configuration_profile"]
        case .mobileConfigurationProfile: keys = ["configuration_profile"]
        case .macApplication: keys = ["mac_application"]
        default: keys = []
        }
        for key in keys {
            if let nested = dictionary[key] as? [String: Any] { return nested }
        }
        return dictionary
    }

    private func groupKindIfNeeded(_ kind: JamfObjectKind, root: [String: Any]) -> JamfObjectKind {
        guard kind == .smartGroup else { return kind }
        if let isSmart = JSONValueReader.bool(root, keys: ["is_smart", "smart", "isSmart"]) {
            return isSmart ? .smartGroup : .staticGroup
        }
        return kind
    }

    private func merge(existing: GraphNode?, incoming: GraphNode) -> GraphNode {
        guard var existing else { return incoming }
        existing.name = existing.name.isEmpty ? incoming.name : existing.name
        existing.category = existing.category ?? incoming.category
        existing.isEnabled = existing.isEnabled ?? incoming.isEnabled
        existing.scopeCount = existing.scopeCount ?? incoming.scopeCount
        existing.rawHash = existing.rawHash ?? incoming.rawHash
        existing.metadata.merge(incoming.metadata) { current, _ in current }
        return existing
    }

    private func scriptSource(in root: [String: Any]) -> String? {
        JSONValueReader.string(root, keys: ["script_contents", "scriptContents", "script", "input_type.script", "inputType.script"])
    }
}

private struct ExtractionContext {
    let nodesByKey: [String: GraphNode]
    let keysByTypeID: [String: String]
    let keysByTypeName: [String: String]
    let groupKeysByID: [String: String]
    let groupKeysByName: [String: String]
    let eaKeysByName: [String: String]

    init(nodes: [GraphNode]) {
        nodesByKey = Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, $0) })
        keysByTypeID = Dictionary(uniqueKeysWithValues: nodes.map { ("\($0.objectType.rawValue):\($0.objectId)", $0.key) })
        keysByTypeName = Dictionary(nodes.map { ("\($0.objectType.rawValue):\($0.name.normalizedLookupKey)", $0.key) }, uniquingKeysWith: { first, _ in first })

        let groups = nodes.filter { $0.objectType == .smartGroup || $0.objectType == .staticGroup }
        groupKeysByID = Dictionary(groups.map { ($0.objectId, $0.key) }, uniquingKeysWith: { first, _ in first })
        groupKeysByName = Dictionary(groups.map { ($0.name.normalizedLookupKey, $0.key) }, uniquingKeysWith: { first, _ in first })
        eaKeysByName = Dictionary(nodes.filter { $0.objectType == .extensionAttribute }.map { ($0.name.normalizedLookupKey, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    func key(type: JamfObjectKind, id: String?, name: String) -> String? {
        if let id, let key = keysByTypeID["\(type.rawValue):\(id)"] {
            return key
        }
        if let key = keysByTypeName["\(type.rawValue):\(name.normalizedLookupKey)"] {
            return key
        }
        return nil
    }

    func groupKey(id: String?, name: String) -> String? {
        if let id, let key = groupKeysByID[id] {
            return key
        }
        return groupKeysByName[name.normalizedLookupKey]
    }

    func extensionAttributeKey(name: String) -> String? {
        eaKeysByName[name.normalizedLookupKey]
    }

    func nodeName(for key: String) -> String? {
        nodesByKey[key]?.name
    }
}

private extension String {
    var normalizedLookupKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

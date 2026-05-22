import Foundation
import JamfMapperCore
import Testing

@Test func detectsDuplicateScripts() async throws {
    let graph = GraphSnapshot(nodes: [
        GraphNode(key: "script:1", objectType: .script, objectId: "1", name: "Install A", rawHash: "same", source: .classic),
        GraphNode(key: "script:2", objectType: .script, objectId: "2", name: "Install B", rawHash: "same", source: .classic)
    ])

    let findings = GraphAnalyzer().analyze(graph: graph)

    #expect(findings.contains { $0.type == .duplicateScript })
}

@Test func detectsCircularSmartGroups() async throws {
    let graph = GraphSnapshot(
        nodes: [
            GraphNode(key: "smartGroup:1", objectType: .smartGroup, objectId: "1", name: "A", source: .classic),
            GraphNode(key: "smartGroup:2", objectType: .smartGroup, objectId: "2", name: "B", source: .classic)
        ],
        edges: [
            GraphEdge(fromKey: "smartGroup:1", toKey: "smartGroup:2", kind: .nestedSmartGroup),
            GraphEdge(fromKey: "smartGroup:2", toKey: "smartGroup:1", kind: .nestedSmartGroup)
        ]
    )

    let findings = GraphAnalyzer().analyze(graph: graph)

    #expect(findings.contains { $0.type == .circularSmartGroup })
}

@Test func extractsPolicyScriptAndPackageEdges() async throws {
    let payload = """
    {
      "policy": {
        "general": { "id": 10, "name": "Deploy Chrome", "enabled": true, "category": { "id": 2, "name": "Apps" } },
        "scripts": { "script": [{ "id": 5, "name": "Installomator" }] },
        "package_configuration": { "packages": { "package": [{ "id": 8, "name": "Chrome.pkg" }] } }
      }
    }
    """.data(using: .utf8)!
    let raw = RawJamfObject(snapshotID: UUID(), objectType: .policy, objectID: "10", name: "Deploy Chrome", source: .classic, endpoint: "/policies/id/10", payload: payload)

    let graph = GraphExtractor().extract(rawObjects: [raw])

    #expect(graph.nodes.contains { $0.key == "policy:10" })
    #expect(graph.edges.contains { $0.kind == .usesScript && $0.toKey == "script:5" })
    #expect(graph.edges.contains { $0.kind == .installsPackage && $0.toKey == "package:8" })
    #expect(graph.edges.contains { $0.kind == .inCategory && $0.toKey == "category:2" })
}

@Test func policyShowsScopedGroupAndEAUsedByGroupCriteria() async throws {
    let snapshotID = UUID()
    let policyPayload = """
    {
      "policy": {
        "general": { "id": 10, "name": "Deploy Chrome", "enabled": true },
        "scope": { "computer_groups": { "computer_group": [{ "id": 7, "name": "Chrome Eligible" }] } }
      }
    }
    """.data(using: .utf8)!
    let groupPayload = """
    {
      "computer_group": {
        "id": 7,
        "name": "Chrome Eligible",
        "is_smart": true,
        "criteria": { "criterion": [{ "name": "Chrome Installed", "search_type": "is", "value": "No" }] }
      }
    }
    """.data(using: .utf8)!
    let eaPayload = """
    {
      "computer_extension_attribute": {
        "id": 44,
        "name": "Chrome Installed",
        "input_type": { "type": "Script", "script": "echo '<result>No</result>'" }
      }
    }
    """.data(using: .utf8)!

    let graph = GraphExtractor().extract(rawObjects: [
        RawJamfObject(snapshotID: snapshotID, objectType: .policy, objectID: "10", name: "Deploy Chrome", source: .classic, endpoint: "/policies/id/10", payload: policyPayload),
        RawJamfObject(snapshotID: snapshotID, objectType: .smartGroup, objectID: "7", name: "Chrome Eligible", source: .classic, endpoint: "/computergroups/id/7", payload: groupPayload),
        RawJamfObject(snapshotID: snapshotID, objectType: .extensionAttribute, objectID: "44", name: "Chrome Installed", source: .classic, endpoint: "/computerextensionattributes/id/44", payload: eaPayload)
    ])

    let sections = DependencyResolver().sections(for: "policy:10", in: graph)
    let allItems = sections.flatMap(\.items)

    #expect(allItems.contains { $0.node.key == "smartGroup:7" && $0.relationship == "Scoped" })
    #expect(sections.contains { $0.title == "Extension Attributes Used By Associated Groups" && $0.items.contains { $0.node.key == "extensionAttribute:44" && $0.via == "Chrome Eligible" } })
}

@Test func scriptShowsPoliciesThatExecuteIt() async throws {
    let graph = GraphSnapshot(
        nodes: [
            GraphNode(key: "policy:10", objectType: .policy, objectId: "10", name: "Deploy Chrome", isEnabled: true, source: .classic),
            GraphNode(key: "script:5", objectType: .script, objectId: "5", name: "Installomator", isEnabled: true, source: .classic)
        ],
        edges: [
            GraphEdge(fromKey: "policy:10", toKey: "script:5", kind: .usesScript)
        ]
    )

    let sections = DependencyResolver().sections(for: "script:5", in: graph)

    #expect(sections.contains { section in
        section.title == "Mapped To / Used By" &&
        section.items.contains { $0.node.key == "policy:10" && $0.relationship == "Executes this script" }
    })
}

@Test func classicListArraysAreParsedAsMultipleObjects() async throws {
    let payload: [String: Any] = [
        "policies": [
            ["id": 1, "name": "One"],
            ["id": 2, "name": "Two"]
        ]
    ]

    let items = JSONValueReader.array(payload["policies"], keys: ["policy", "policies"])

    #expect(items.count == 2)
    #expect(JSONValueReader.string(items[0], keys: ["name"]) == "One")
    #expect(JSONValueReader.string(items[1], keys: ["id"]) == "2")
}

@Test func packageNameAndEAEmbeddedScriptNamesAreReadable() async throws {
    let snapshotID = UUID()
    let packagePayload = """
    { "package": { "id": 8, "packageName": "Google Chrome", "fileName": "Chrome.pkg" } }
    """.data(using: .utf8)!
    let eaPayload = """
    {
      "computer_extension_attribute": {
        "id": 44,
        "name": "Chrome Installed",
        "input_type": { "type": "Script", "script": "echo '<result>No</result>'" }
      }
    }
    """.data(using: .utf8)!

    let graph = GraphExtractor().extract(rawObjects: [
        RawJamfObject(snapshotID: snapshotID, objectType: .package, objectID: "8", name: "Chrome.pkg", source: .classic, endpoint: "/packages/id/8", payload: packagePayload),
        RawJamfObject(snapshotID: snapshotID, objectType: .extensionAttribute, objectID: "44", name: "Chrome Installed", source: .classic, endpoint: "/computerextensionattributes/id/44", payload: eaPayload)
    ])

    #expect(graph.nodes.contains { $0.key == "package:8" && $0.name == "Google Chrome" })
    #expect(graph.nodes.contains { $0.key == "script:embedded-ea-44" && $0.name == "Chrome Installed embedded script" && $0.objectType == .script })
    #expect(graph.nodes.contains { $0.key == "extensionAttribute:44" && $0.metadata["scriptSource"] == "echo '<result>No</result>'" })
    #expect(graph.nodes.contains { $0.key == "script:embedded-ea-44" && $0.metadata["scriptSource"] == "echo '<result>No</result>'" })
}

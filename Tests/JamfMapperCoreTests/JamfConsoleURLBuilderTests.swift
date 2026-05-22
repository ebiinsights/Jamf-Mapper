import Foundation
import JamfMapperCore
import Testing

@Test func buildsJamfCloudConsoleLinksFromObjectExamples() async throws {
    let baseURL = try #require(URL(string: "https://commonplacedigital.jamfcloud.com"))
    let examples: [(GraphNode, String)] = [
        (node(.package, id: "13"), "https://commonplacedigital.jamfcloud.com/view/settings/computer-management/packages/13?tab=general"),
        (node(.computerConfigurationProfile, id: "9"), "https://commonplacedigital.jamfcloud.com/OSXConfigurationProfiles.html?id=9&o=r"),
        (node(.policy, id: "5"), "https://commonplacedigital.jamfcloud.com/policies.html?id=5&o=r"),
        (node(.restrictedSoftware, id: "1"), "https://commonplacedigital.jamfcloud.com/restrictedSoftware.html?id=1&o=r"),
        (node(.appInstaller, id: "37"), "https://commonplacedigital.jamfcloud.com/view/computers/mac-apps/app-installers/deployments/37"),
        (node(.patchPolicy, id: "40"), "https://commonplacedigital.jamfcloud.com/view/computers/patch/40?tab=report"),
        (node(.smartGroup, id: "53"), "https://commonplacedigital.jamfcloud.com/smartComputerGroups.html?id=53&o=r"),
        (node(.staticGroup, id: "5"), "https://commonplacedigital.jamfcloud.com/staticComputerGroups.html?id=5&o=r"),
        (node(.computerPrestage, id: "1"), "https://commonplacedigital.jamfcloud.com/computerEnrollmentPrestage.html?id=1&o=r"),
        (node(.extensionAttribute, id: "4"), "https://commonplacedigital.jamfcloud.com/view/settings/computer-management/computer-extension-attributes/4"),
        (node(.script, id: "31"), "https://commonplacedigital.jamfcloud.com/view/settings/computer-management/scripts/31?tab=general")
    ]

    for (node, expectedURL) in examples {
        #expect(JamfConsoleURLBuilder.url(for: node, baseURL: baseURL)?.absoluteString == expectedURL)
    }
}

@Test func embeddedEAScriptOpensSourceEAConsoleLink() async throws {
    let baseURL = try #require(URL(string: "https://commonplacedigital.jamfcloud.com/"))
    let embeddedScript = GraphNode(
        key: "script:embedded-ea-4",
        objectType: .script,
        objectId: "embedded-ea-4",
        name: "Example EA embedded script",
        source: .derived,
        metadata: ["sourceEAId": "4"]
    )

    #expect(JamfConsoleURLBuilder.url(for: embeddedScript, baseURL: baseURL)?.absoluteString == "https://commonplacedigital.jamfcloud.com/view/settings/computer-management/computer-extension-attributes/4")
}

private func node(_ kind: JamfObjectKind, id: String) -> GraphNode {
    GraphNode(
        key: GraphNode.key(for: kind, id: id),
        objectType: kind,
        objectId: id,
        name: "\(kind.rawValue) \(id)",
        source: .classic
    )
}

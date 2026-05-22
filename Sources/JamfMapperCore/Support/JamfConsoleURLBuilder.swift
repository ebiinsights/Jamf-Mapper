import Foundation

public enum JamfConsoleURLBuilder {
    public static func url(for node: GraphNode, baseURL: URL) -> URL? {
        guard let path = path(for: node) else { return nil }
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let separator = path.hasPrefix("/") ? "" : "/"
        return URL(string: "\(base)\(separator)\(path)")
    }

    public static func path(for node: GraphNode) -> String? {
        guard node.metadata["unresolved"] != "true" else { return nil }

        switch node.objectType {
        case .policy:
            return "policies.html?id=\(node.objectId)&o=r"
        case .smartGroup:
            return "smartComputerGroups.html?id=\(node.objectId)&o=r"
        case .staticGroup:
            return "staticComputerGroups.html?id=\(node.objectId)&o=r"
        case .extensionAttribute:
            return "view/settings/computer-management/computer-extension-attributes/\(node.objectId)"
        case .script:
            if let sourceEAId = node.metadata["sourceEAId"] {
                return "view/settings/computer-management/computer-extension-attributes/\(sourceEAId)"
            }
            return "view/settings/computer-management/scripts/\(node.objectId)?tab=general"
        case .package:
            return "view/settings/computer-management/packages/\(node.objectId)?tab=general"
        case .computerConfigurationProfile:
            return "OSXConfigurationProfiles.html?id=\(node.objectId)&o=r"
        case .restrictedSoftware:
            return "restrictedSoftware.html?id=\(node.objectId)&o=r"
        case .appInstaller:
            return "view/computers/mac-apps/app-installers/deployments/\(node.objectId)"
        case .patchPolicy, .patchTitle, .patchSoftwareTitleConfiguration:
            return "view/computers/patch/\(node.objectId)?tab=report"
        case .computerPrestage:
            return "computerEnrollmentPrestage.html?id=\(node.objectId)&o=r"
        case .category:
            return "categories.html?id=\(node.objectId)&o=r"
        case .advancedSearch:
            return "advancedComputerSearches.html?id=\(node.objectId)&o=r"
        case .printer:
            return "computerManagement.html?tab=printers&view=details&id=\(node.objectId)"
        case .dockItem:
            return "computerManagement.html?tab=dockItems&view=details&id=\(node.objectId)"
        case .directoryBinding:
            return "computerManagement.html?tab=directoryBindings&view=details&id=\(node.objectId)"
        case .networkSegment:
            return "networkSegments.html?id=\(node.objectId)&o=r"
        case .mobileConfigurationProfile:
            return "mobileDeviceConfigurationProfiles.html?id=\(node.objectId)&o=r"
        case .macApplication:
            return "macApplications.html?id=\(node.objectId)&o=r"
        case .jamfConnectProfile:
            return "jamfConnect.html"
        case .ddmDeclaration:
            return "declarativeManagement.html"
        case .unknown:
            return nil
        }
    }
}

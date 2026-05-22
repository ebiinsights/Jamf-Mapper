import Foundation

public struct ClassicEndpoint: Sendable {
    public var kind: JamfObjectKind
    public var collectionPath: String
    public var rootKey: String
    public var itemKey: String

    public init(kind: JamfObjectKind, collectionPath: String, rootKey: String, itemKey: String) {
        self.kind = kind
        self.collectionPath = collectionPath
        self.rootKey = rootKey
        self.itemKey = itemKey
    }
}

public enum JamfEndpointCatalog {
    public static let classicCore: [ClassicEndpoint] = [
        .init(kind: .policy, collectionPath: "/policies", rootKey: "policies", itemKey: "policy"),
        .init(kind: .smartGroup, collectionPath: "/computergroups", rootKey: "computer_groups", itemKey: "computer_group"),
        .init(kind: .extensionAttribute, collectionPath: "/computerextensionattributes", rootKey: "computer_extension_attributes", itemKey: "computer_extension_attribute"),
        .init(kind: .script, collectionPath: "/scripts", rootKey: "scripts", itemKey: "script"),
        .init(kind: .category, collectionPath: "/categories", rootKey: "categories", itemKey: "category"),
        .init(kind: .advancedSearch, collectionPath: "/advancedcomputersearches", rootKey: "advanced_computer_searches", itemKey: "advanced_computer_search"),
        .init(kind: .restrictedSoftware, collectionPath: "/restrictedsoftware", rootKey: "restricted_software", itemKey: "restricted_software"),
        .init(kind: .package, collectionPath: "/packages", rootKey: "packages", itemKey: "package"),
        .init(kind: .printer, collectionPath: "/printers", rootKey: "printers", itemKey: "printer"),
        .init(kind: .dockItem, collectionPath: "/dockitems", rootKey: "dock_items", itemKey: "dock_item"),
        .init(kind: .directoryBinding, collectionPath: "/directorybindings", rootKey: "directory_bindings", itemKey: "directory_binding"),
        .init(kind: .networkSegment, collectionPath: "/networksegments", rootKey: "network_segments", itemKey: "network_segment"),
        .init(kind: .computerConfigurationProfile, collectionPath: "/osxconfigurationprofiles", rootKey: "os_x_configuration_profiles", itemKey: "os_x_configuration_profile"),
        .init(kind: .mobileConfigurationProfile, collectionPath: "/mobiledeviceconfigurationprofiles", rootKey: "configuration_profiles", itemKey: "configuration_profile"),
        .init(kind: .macApplication, collectionPath: "/macapplications", rootKey: "mac_applications", itemKey: "mac_application")
    ]

    public static let proCollections: [(kind: JamfObjectKind, path: String)] = [
        (.script, "/api/v1/scripts"),
        (.package, "/api/v1/packages"),
        (.extensionAttribute, "/api/v1/computer-extension-attributes"),
        (.smartGroup, "/api/v2/computer-groups/smart-groups"),
        (.staticGroup, "/api/v2/computer-groups/static-groups"),
        (.patchPolicy, "/api/v2/patch-policies/policy-details"),
        (.patchSoftwareTitleConfiguration, "/api/v2/patch-software-title-configurations"),
        (.jamfConnectProfile, "/api/v1/jamf-connect/config-profiles"),
        (.computerPrestage, "/api/v3/computer-prestages")
    ]
}
